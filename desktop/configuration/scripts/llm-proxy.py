#!/usr/bin/env python3
"""Sanitising reverse proxy that puts ollama on the public internet.

Everything here exists because ollama's API assumes a trusted caller. It has
no authentication, it will pull and delete models for anyone who asks, and --
the part that actually costs a reboot -- it accepts a per-request num_ctx that
can push the card past what its allocator can work in. See the measured table
in ../services.nix: 224k reports as 100% GPU and runs at a tenth speed, and the
256k attempt OOM-killed llama-server and left a thread wedged in
kfd_process_notifier_release_internal holding 22 GiB until reboot.

So this is a request sanitiser first and a gateway second. The auth is thin on
purpose (two static keys); the body rewriting is where the protection is.

Exposed by `tailscale funnel`, which means public and unauthenticated at the
transport layer: funnel gets a real Let's Encrypt cert, that cert lands in
Certificate Transparency logs, and the hostname is enumerable from those logs
within minutes. Nothing here may assume the URL is a secret.
"""

import asyncio
import hashlib
import hmac
import json
import logging
import os
import sys
import time
from collections import defaultdict, deque
from datetime import datetime
from zoneinfo import ZoneInfo

from aiohttp import ClientSession, ClientTimeout, web

log = logging.getLogger("llm-proxy")

# --- configuration ---------------------------------------------------------

LISTEN_HOST = os.environ.get("PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("PROXY_PORT", "8080"))
OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")

# Pinned server-side. A client-chosen model is a VRAM-thrash vector (swapping
# models evicts the resident one) and a way to load something that does not fit.
MODEL = os.environ.get("PROXY_MODEL", "qwen3.8:160k")

# The name shown to callers, which is deliberately NOT the upstream one. MODEL
# changes with the profile -- "qwen3.8:160k" on the ollama rung, "qwen3.8" on
# the llama-server rungs -- and sanitise() overwrites whatever a client sends
# with it anyway, so the advertised name is free to be stable. It has to be:
# the page hands out a config block people paste into a file, and it should not
# rot the next time the scaler changes engine.
PUBLIC_MODEL = "qwen3.8"

# Held under the slot's context window so there is room for the reply. The
# count is an estimate (see estimate_tokens); the margin absorbs its error.
#
# These defaults are the no-window fallback: one slot on ollama at 160k, which
# is also the ladder's first rung. During the window llm-scaler.py overrides
# all of them -- and OLLAMA_URL -- from /run/llm-window.env to match whichever
# engine and profile is loaded.
MAX_PROMPT_TOKENS = int(os.environ.get("PROXY_MAX_PROMPT_TOKENS", "125000"))
MAX_OUTPUT_TOKENS = int(os.environ.get("PROXY_MAX_OUTPUT_TOKENS", "8192"))

# Must match OLLAMA_NUM_PARALLEL, which llm-scaler.py writes into the same
# file. More here than there just moves the queue from ollama into the proxy;
# fewer wastes KV cache the card already paid for.
SLOTS = int(os.environ.get("PROXY_SLOTS", "1"))
QUEUE_TIMEOUT = float(os.environ.get("PROXY_QUEUE_TIMEOUT", "300"))

RATE_LIMIT_REQUESTS = int(os.environ.get("PROXY_RATE_LIMIT", "60"))
RATE_LIMIT_WINDOW = 60.0

# Where the demand snapshot is written for llm-scaler to read. A file rather
# than an HTTP endpoint on purpose: every route this process serves is reachable
# from the funnel, so a /metrics route would publish usage patterns to anyone
# holding a key, and gating it behind its own auth means the scaler needs a key
# of its own. A file in RuntimeDirectory is readable by root and by nothing
# else, and it costs no attack surface at all.
DEMAND_PATH = os.environ.get("PROXY_DEMAND_PATH", "/run/llm-proxy/demand.json")

# Reservations outlive this process on purpose -- see the Reservations
# docstring. StateDirectory, not RuntimeDirectory, which is cleaned on stop.
RESERVATION_PATH = os.environ.get("PROXY_RESERVATION_PATH", "/var/lib/llm-proxy/reservations.json")
RESERVATION_TTL = float(os.environ.get("PROXY_RESERVATION_TTL", "1800"))
DEMAND_WINDOW = float(os.environ.get("PROXY_DEMAND_WINDOW", "3600"))
DEMAND_INTERVAL = 15.0

# Second gate behind the funnel on/off timer. The timer is the real boundary;
# this catches the case where it failed to fire and the tunnel stayed up.
TZ = ZoneInfo(os.environ.get("PROXY_TZ", "America/Toronto"))
WINDOW_START = int(os.environ.get("PROXY_WINDOW_START", "3"))
WINDOW_END = int(os.environ.get("PROXY_WINDOW_END", "11"))
WINDOW_ENABLED = os.environ.get("PROXY_WINDOW", "1") == "1"

# Only these reach ollama. An allowlist rather than a deny-list for /api/pull
# and /api/delete, so an endpoint added by a future ollama release is closed by
# default instead of being a hole nobody noticed opening.
ALLOWED = {("POST", "/v1/chat/completions"), ("GET", "/v1/models"), ("GET", "/healthz")}

# Reachable without a bearer token. The page has to render before anyone has
# typed a key, and the status it shows -- how many slots exist and when the
# next one frees -- is the whole point of publishing it. Everything these two
# reveal (that the service exists, its hours, its capacity) is already implied
# by the funnel's certificate being in the CT logs.
PUBLIC = {("GET", "/"), ("GET", "/status")}

# Takes a key in the body rather than a header, because it is posted by a form.
RESERVE = {("POST", "/reserve"), ("POST", "/release")}

# Passed through to ollama untouched. Anything absent here is dropped -- most
# importantly options, num_ctx and keep_alive, which are the three ways a
# client can reach past the request and affect the server's memory state.
BODY_PASSTHROUGH = {
    "messages", "temperature", "top_p", "top_k", "stop", "seed", "stream",
    "stream_options", "presence_penalty", "frequency_penalty", "tools",
    "tool_choice", "response_format", "logprobs", "top_logprobs", "n",
}

# --- auth ------------------------------------------------------------------


def load_keys():
    """Read bearer keys from the systemd credential, one per line.

    LoadCredential rather than an EnvironmentFile because systemd reads it as
    root and exposes it to the DynamicUser, so the sops secret stays root-owned
    0400 and no static account is needed -- same reasoning as litellm.nix.
    """
    creds = os.environ.get("CREDENTIALS_DIRECTORY")
    path = os.path.join(creds, "keys") if creds else os.environ.get("PROXY_KEYS_FILE")
    if not path:
        log.error("no credential directory and no PROXY_KEYS_FILE; refusing to start")
        sys.exit(1)
    with open(path) as f:
        keys = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    if not keys:
        log.error("key file %s is empty; refusing to start", path)
        sys.exit(1)
    log.info("loaded %d key(s)", len(keys))
    return keys


def key_id(key):
    """Short stable label for logs. Never log the key itself."""
    return hashlib.sha256(key.encode()).hexdigest()[:8]


def authenticate(request, keys):
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    presented = header[7:].strip()
    # compare_digest against every key rather than a set lookup, so the work
    # does not depend on how much of a guess was correct.
    matched = None
    for k in keys:
        if hmac.compare_digest(presented, k):
            matched = k
    return matched


# --- guards ----------------------------------------------------------------


def in_window(now=None):
    if not WINDOW_ENABLED:
        return True
    hour = (now or datetime.now(TZ)).hour
    if WINDOW_START <= WINDOW_END:
        return WINDOW_START <= hour < WINDOW_END
    return hour >= WINDOW_START or hour < WINDOW_END


def estimate_tokens(messages):
    """Character-based estimate, deliberately pessimistic.

    A real tokeniser would mean pulling transformers in for one number. The
    point of the check is not accuracy, it is refusing to hand ollama a prompt
    it would silently truncate: a ~200k-token prompt came back as 81922
    prompt_tokens (litellm.nix), which reads to the caller as the model going
    senile rather than as an error. 3.0 chars/token under-counts real text, so
    the estimate errs toward rejecting.
    """
    chars = 0
    for m in messages if isinstance(messages, list) else []:
        content = m.get("content") if isinstance(m, dict) else None
        if isinstance(content, str):
            chars += len(content)
        elif isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and isinstance(part.get("text"), str):
                    chars += len(part["text"])
    return int(chars / 3.0)


def sanitise(body):
    """Rebuild the request from an allowlist. Returns (body, error)."""
    if not isinstance(body, dict):
        return None, "body must be a JSON object"
    messages = body.get("messages")
    if not isinstance(messages, list) or not messages:
        return None, "messages must be a non-empty array"

    est = estimate_tokens(messages)
    if est > MAX_PROMPT_TOKENS:
        return None, (
            f"prompt is roughly {est} tokens, over the {MAX_PROMPT_TOKENS} limit. "
            "Rejected rather than silently truncated."
        )

    out = {k: v for k, v in body.items() if k in BODY_PASSTHROUGH}
    out["model"] = MODEL

    requested = body.get("max_tokens") or body.get("max_completion_tokens")
    try:
        requested = int(requested)
    except (TypeError, ValueError):
        requested = MAX_OUTPUT_TOKENS
    out["max_tokens"] = max(1, min(requested, MAX_OUTPUT_TOKENS))

    # Usage on streamed replies is opt-in; ask for it so the logs can record
    # real token counts instead of the estimate above.
    if out.get("stream"):
        opts = out.get("stream_options")
        out["stream_options"] = {**opts, "include_usage": True} if isinstance(opts, dict) else {"include_usage": True}

    return out, None


class RateLimiter:
    def __init__(self):
        self.hits = defaultdict(deque)

    def allow(self, ident):
        now = time.monotonic()
        q = self.hits[ident]
        while q and now - q[0] > RATE_LIMIT_WINDOW:
            q.popleft()
        if len(q) >= RATE_LIMIT_REQUESTS:
            return False
        q.append(now)
        return True


class Demand:
    """Rolling picture of how busy the window actually is.

    The scaler needs to answer one question -- "how many callers want the card
    at the same time?" -- and the honest signal for it is concurrency, not
    request count. Ten requests an hour from one caller is a single-slot
    workload; three simultaneous callers is not, however few requests they send.

    Peak rather than mean concurrency, because the cost of under-provisioning
    is a caller sitting in the queue for up to QUEUE_TIMEOUT and the cost of
    over-provisioning is some KV cache nobody reads. Those are not symmetric.
    """

    def __init__(self):
        self.active = 0
        self.starts = deque()     # (ts, kid) -- one per accepted request
        self.waits = deque()      # (ts, seconds spent queueing)
        self.rejects = deque()    # ts of "all slots busy" refusals
        self.samples = deque()    # (ts, active) -- concurrency, sampled on change

    def _trim(self, now):
        for q in (self.starts, self.waits, self.rejects, self.samples):
            while q and now - q[0][0] > DEMAND_WINDOW:
                q.popleft()

    def begin(self, kid, waited):
        now = time.time()
        self.active += 1
        self.starts.append((now, kid))
        self.waits.append((now, waited))
        self.samples.append((now, self.active))
        self._trim(now)

    def end(self):
        self.active = max(0, self.active - 1)
        self.samples.append((time.time(), self.active))

    def reject(self):
        now = time.time()
        self.rejects.append((now,))
        self._trim(now)

    def snapshot(self):
        now = time.time()
        self._trim(now)
        waits = sorted(w for _, w in self.waits)
        return {
            "ts": now,
            "slots": SLOTS,
            "model": MODEL,
            "window_seconds": DEMAND_WINDOW,
            "active": self.active,
            # The number the scaler keys on.
            "peak_concurrency": max((a for _, a in self.samples), default=self.active),
            "requests": len(self.starts),
            "distinct_keys": len({kid for _, kid in self.starts}),
            # Queueing that actually happened is the direct evidence that the
            # slot count is too low; rejects are the same evidence, louder.
            "queued_requests": sum(1 for w in waits if w > 1.0),
            "max_wait_seconds": waits[-1] if waits else 0.0,
            "rejects": len(self.rejects),
        }


async def demand_writer(app):
    """Write the snapshot on a timer, not on every request.

    On a timer because the scaler polls on a timer too and a write per request
    would be pure churn; and because a snapshot that keeps being refreshed while
    nothing happens is how the scaler tells "idle" from "proxy is dead", which
    are decisions it must not confuse -- reloading the model because the proxy
    crashed would be exactly wrong.
    """
    path = DEMAND_PATH
    tmp = path + ".tmp"
    try:
        while True:
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                snap = app["demand"].snapshot()
                # Reservations ride along in the same file so the scaler has
                # one thing to read and one moment to read it -- two files
                # would let it see slots reserved under a profile that had
                # already changed.
                resv = app["reservations"]
                held = resv.active()
                snap["reserved"] = len(held)
                snap["reserved_until"] = max(held.values()) if held else 0
                # Callers who wanted a reservation and could not have one. This
                # is demand that leaves no other trace: they are turned away at
                # the page, so they never reach a slot and never queue.
                snap["reservation_denials"] = len(resv.denials)
                with open(tmp, "w") as f:
                    json.dump(snap, f)
                os.replace(tmp, path)
            except OSError as e:
                log.warning("demand snapshot failed: %s", e)
            await asyncio.sleep(DEMAND_INTERVAL)
    except asyncio.CancelledError:
        raise


class Reservations:
    """Thirty-minute holds that let more keys exist than there are slots.

    A reservation is the answer to "will I get kicked off halfway through?".
    Without one, a caller competes for a slot on every single request, so a
    long session is a series of chances to lose. With one, a slot is set aside
    for that key for the duration and nobody else can take it -- which is only
    a real guarantee if unreserved traffic is kept out of reserved capacity
    entirely, so that is what admit() does. The cost is that a reserved slot
    sits idle while its holder is thinking, and that is the point: idle is what
    "reserved" means.

    Persisted, because llm-scaler restarts this process when it changes profile
    and an in-memory hold would evaporate exactly when someone was relying on
    it. The file lives in StateDirectory rather than RuntimeDirectory for the
    same reason -- RuntimeDirectory is cleaned on stop.
    """

    def __init__(self, path, ttl):
        self.path = path
        self.ttl = ttl
        self.held = {}      # kid -> expiry epoch
        self.denials = deque()  # ts of "no slot free to reserve"
        self._load()

    def _load(self):
        try:
            with open(self.path) as f:
                data = json.load(f)
            now = time.time()
            self.held = {k: v for k, v in data.get("held", {}).items() if v > now}
        except (OSError, ValueError):
            self.held = {}

    def _save(self):
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"held": self.held}, f)
            os.replace(tmp, self.path)
        except OSError as e:
            log.warning("reservation save failed: %s", e)

    def prune(self, now=None):
        now = now or time.time()
        expired = [k for k, v in self.held.items() if v <= now]
        for k in expired:
            del self.held[k]
        while self.denials and now - self.denials[0] > DEMAND_WINDOW:
            self.denials.popleft()
        return expired

    def active(self):
        self.prune()
        return dict(self.held)

    def holds(self, kid):
        self.prune()
        return kid in self.held

    def reserve(self, kid, slots):
        """Grant or extend. Returns (ok, expiry_or_next_free).

        Extending an existing hold rather than refusing it: a caller who is
        still working at minute 29 should not have to lose the slot and race
        for it again, and letting them extend costs nothing that refusing them
        would save -- they are holding the slot either way.
        """
        now = time.time()
        self.prune(now)
        if kid not in self.held and len(self.held) >= slots:
            self.denials.append(now)
            return False, min(self.held.values()) if self.held else now
        self.held[kid] = now + self.ttl
        self._save()
        return True, self.held[kid]

    def release(self, kid):
        self.prune()
        if kid in self.held:
            del self.held[kid]
            self._save()
            return True
        return False


class Slots:
    """Admission control that keeps reserved capacity genuinely reserved.

    Two pools out of the same N. Each active reservation carves one slot out
    for its holder; whatever is left is what unreserved callers compete for.
    They are kept strictly apart on purpose -- letting an unreserved request
    borrow an idle reserved slot would give back the throughput but take away
    the only thing a reservation is for, since the holder would then have to
    wait for that borrower to finish.

    A Condition rather than a Semaphore because the capacity available to
    unreserved callers moves as reservations come and go, and a Semaphore's
    count cannot be resized underneath its waiters.
    """

    def __init__(self, total):
        self.total = total
        self.cond = asyncio.Condition()
        self.busy_reserved = set()
        self.busy_general = 0

    def general_capacity(self, reserved_count):
        return max(0, self.total - reserved_count)

    def _can_admit(self, kid, is_reserved, reserved_count):
        if is_reserved:
            # One slot per reservation, not per request: a holder firing two
            # requests at once would otherwise eat a general slot for the
            # second and starve somebody who has no reservation at all.
            return kid not in self.busy_reserved
        return self.busy_general < self.general_capacity(reserved_count)

    async def acquire(self, kid, is_reserved, reserved_count_fn, timeout):
        # A plain def, emphatically not an "async def". Condition.wait_for
        # takes a callable returning a bool; hand it a coroutine function and
        # it tests the coroutine OBJECT for truth, which is always true -- so
        # every caller is admitted instantly and the reservation guarantee
        # silently evaporates. It looks completely correct while doing nothing.
        def ready():
            return self._can_admit(kid, is_reserved, reserved_count_fn())

        async with self.cond:
            await asyncio.wait_for(self.cond.wait_for(ready), timeout=timeout)
            if is_reserved:
                self.busy_reserved.add(kid)
            else:
                self.busy_general += 1

    async def release(self, kid, is_reserved):
        async with self.cond:
            if is_reserved:
                self.busy_reserved.discard(kid)
            else:
                self.busy_general = max(0, self.busy_general - 1)
            self.cond.notify_all()

    def in_flight(self):
        return len(self.busy_reserved) + self.busy_general


# Inlined rather than served from a file: it is one page, it has no assets, and
# a served directory is another thing reachable from the funnel. Deliberately
# plain -- no external fonts, no CDN, nothing that phones anywhere.
PAGE = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>slot reservation</title>
<style>
 :root { color-scheme: light dark; --fg:#111; --bg:#fafafa; --mut:#666; --line:#ddd; --ok:#0a6b3d; --bad:#8a2020; }
 @media (prefers-color-scheme: dark) { :root { --fg:#e8e8e8; --bg:#151515; --mut:#999; --line:#333; --ok:#4ade80; --bad:#f87171; } }
 body { font: 15px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--fg);
        background: var(--bg); margin: 0; padding: 2.5rem 1.25rem; }
 main { max-width: 32rem; margin: 0 auto; }
 h1 { font-size: 1.1rem; font-weight: 600; margin: 0 0 .35rem; }
 p.sub { color: var(--mut); margin: 0 0 1.75rem; }
 .card { border: 1px solid var(--line); border-radius: 8px; padding: 1.1rem 1.2rem; margin-bottom: 1rem; }
 .row { display: flex; justify-content: space-between; gap: 1rem; padding: .3rem 0; }
 .row span:last-child { color: var(--mut); }
 form { display: flex; gap: .5rem; margin-top: .25rem; }
 input { flex: 1; min-width: 0; font: inherit; padding: .5rem .6rem; border: 1px solid var(--line);
         border-radius: 6px; background: var(--bg); color: var(--fg); }
 button { font: inherit; padding: .5rem 1rem; border: 1px solid var(--line); border-radius: 6px;
          background: var(--fg); color: var(--bg); cursor: pointer; }
 button:disabled { opacity: .5; cursor: default; }
 #msg { margin-top: .9rem; min-height: 1.4rem; }
 .ok { color: var(--ok); } .bad { color: var(--bad); }
 code { color: var(--mut); }
 pre { margin: 0; padding: .85rem; border: 1px solid var(--line); border-radius: 6px;
       overflow-x: auto; font-size: 12.5px; line-height: 1.45; background: var(--bg); }
 button.small { padding: .2rem .7rem; font-size: 13px; }
</style>
<main>
<h1>qwen3.8 &mdash; slot reservation</h1>
<p class="sub">Hold a slot for %(ttl_min)d minutes so a long session is not interrupted.</p>

<div class="card">
  <div class="row"><span>service hours</span><span>%(start)02d:00&ndash;%(end)02d:00 %(tz)s</span></div>
  <div class="row"><span>status</span><span id="s-open">&hellip;</span></div>
  <div class="row"><span>slots</span><span id="s-slots">&hellip;</span></div>
  <div class="row"><span>free to reserve</span><span id="s-free">&hellip;</span></div>
  <div class="row"><span>next slot frees</span><span id="s-next">&hellip;</span></div>
</div>

<div class="card">
  <form id="f">
    <input id="k" type="password" placeholder="your key (sk-...)" autocomplete="off" spellcheck="false">
    <button id="b" type="submit">Reserve</button>
  </form>
  <div id="msg"></div>
</div>

<div class="card">
  <div class="row" style="padding-bottom:.6rem">
    <span>opencode config</span>
    <button id="c" type="button" class="small">Copy</button>
  </div>
  <pre id="cfg">&hellip;</pre>
  <p class="sub" style="margin:.8rem 0 0">Drop into <code>~/.config/opencode/opencode.json</code>.
  Any OpenAI-compatible client works too &mdash; base URL <code>%(base)s/v1</code>, same key.</p>
</div>

<p class="sub">Reserving again before it lapses extends the hold.</p>
</main>
<script>
const $ = i => document.getElementById(i);
const fmt = t => t ? new Date(t*1000).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) : '\\u2014';

async function refresh() {
  try {
    const r = await fetch('status', {cache:'no-store'});
    const d = await r.json();
    $('s-open').textContent  = d.in_window ? 'open' : 'closed';
    $('s-slots').textContent = d.slots;
    $('s-free').textContent  = d.slots - d.reserved;
    $('s-next').textContent  = d.reserved >= d.slots ? fmt(d.next_free) : 'now';
    $('b').disabled = !d.in_window;
    renderConfig(d);
  } catch (e) { /* transient; the next tick will pick it up */ }
}

let lastStatus = null;
function renderConfig(d) {
  lastStatus = d;
  const key = $('k').value.trim() || 'sk-YOUR-KEY-HERE';
  const cfg = {
    "$schema": "https://opencode.ai/config.json",
    provider: {
      codebam: {
        npm: "@ai-sdk/openai-compatible",
        name: "codebam qwen3.8",
        options: {baseURL: location.origin + '/v1', apiKey: key},
        models: {
          // The served model is pinned by the proxy; a client-chosen one is
          // rewritten, so this name has to match what /status reports.
          [d.model]: {
            name: "qwen3.8 27B",
            tool_call: true,
            reasoning: true,
            limit: {
              context: d.max_prompt_tokens + d.max_output_tokens,
              input: d.max_prompt_tokens,
              output: d.max_output_tokens
            }
          }
        }
      }
    },
    model: "codebam/" + d.model
  };
  $('cfg').textContent = JSON.stringify(cfg, null, 2);
}

// Re-render as the key is typed, so what you copy already has your key in it.
$('k').addEventListener('input', () => { if (lastStatus) renderConfig(lastStatus); });

$('c').addEventListener('click', async () => {
  const t = $('cfg').textContent;
  try {
    await navigator.clipboard.writeText(t);
    $('c').textContent = 'Copied';
  } catch (e) {
    // clipboard needs a secure context; select it so ctrl-c still works
    const r = document.createRange();
    r.selectNodeContents($('cfg'));
    getSelection().removeAllRanges();
    getSelection().addRange(r);
    $('c').textContent = 'Select+copy';
  }
  setTimeout(() => { $('c').textContent = 'Copy'; }, 1800);
});

$('f').addEventListener('submit', async ev => {
  ev.preventDefault();
  const key = $('k').value.trim();
  if (!key) return;
  $('b').disabled = true;
  $('msg').textContent = 'reserving\\u2026';
  $('msg').className = '';
  try {
    const r = await fetch('reserve', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({key})
    });
    const d = await r.json();
    if (r.ok) {
      $('msg').textContent = 'Slot held until ' + fmt(d.expires_at) + '.';
      $('msg').className = 'ok';
    } else {
      $('msg').textContent = (d.error && d.error.message) || 'could not reserve';
      $('msg').className = 'bad';
    }
  } catch (e) {
    $('msg').textContent = 'network error';
    $('msg').className = 'bad';
  }
  $('b').disabled = false;
  refresh();
});

refresh();
setInterval(refresh, 15000);
</script>
"""


# --- handlers --------------------------------------------------------------


def problem(status, message, **extra):
    return web.json_response({"error": {"message": message, "type": "proxy_error", **extra}}, status=status)


def public_status(app):
    resv = app["reservations"]
    held = resv.active()
    now = time.time()
    return {
        "in_window": in_window(),
        "slots": SLOTS,
        "reserved": len(held),
        # Only meaningful when everything is held; the page shows "now"
        # otherwise. min() of the expiries is when the first one lapses.
        "next_free": min(held.values()) if held else now,
        "window_start": WINDOW_START,
        "window_end": WINDOW_END,
        "reservation_ttl": RESERVATION_TTL,
        # The page builds a drop-in opencode provider block out of these, so
        # they have to be the live values rather than anything hardcoded: the
        # prompt cap moves with the profile (125840 on the one-slot ollama
        # rung, 65936 on the three-slot one), and opencode computes its
        # auto-compaction threshold from it.
        "model": PUBLIC_MODEL,
        "max_prompt_tokens": MAX_PROMPT_TOKENS,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
    }


async def handle_reserve(request, release=False):
    """Key in the JSON body, because a browser form cannot set a header.

    Rate-limited by client address rather than by key: the key is what is being
    guessed, so it cannot be the thing that identifies the guesser. Keys are 48
    hex characters and not realistically brute-forceable, but an endpoint that
    validates secrets and is reachable from the open internet should cost
    something to hammer regardless.
    """
    app = request.app
    # X-Real-IP, not X-Forwarded-For. nginx sets X-Real-IP to $remote_addr,
    # which a client cannot influence, whereas recommendedProxySettings builds
    # X-Forwarded-For with $proxy_add_x_forwarded_for -- it APPENDS to whatever
    # the client sent, so trusting the first entry lets a caller mint a fresh
    # rate-limit bucket per request on the one endpoint that validates keys.
    peer = request.headers.get("X-Real-IP", "").strip() or (request.remote or "?")
    if not app["limiter"].allow(f"ip:{peer}"):
        return problem(429, f"rate limit is {RATE_LIMIT_REQUESTS} requests per minute")

    try:
        body = await request.json()
    except Exception:
        return problem(400, "body is not valid JSON")

    presented = (body.get("key") or "").strip()
    matched = None
    for k in app["keys"]:
        if hmac.compare_digest(presented, k):
            matched = k
    if matched is None:
        log.info("reserve: bad key from %s", peer)
        return problem(401, "that key is not recognised")

    kid = key_id(matched)
    resv = app["reservations"]

    if release:
        resv.release(kid)
        return web.json_response({"ok": True, **public_status(app)})

    if not in_window():
        return problem(
            503, f"outside service hours ({WINDOW_START:02d}:00-{WINDOW_END:02d}:00 {TZ.key})"
        )

    ok, when = resv.reserve(kid, SLOTS)
    if not ok:
        log.info("reserve: kid=%s refused, all %d slots held", kid, SLOTS)
        return problem(
            503,
            f"all {SLOTS} slot(s) are reserved right now; the next frees at "
            f"{datetime.fromtimestamp(when, TZ).strftime('%H:%M')}",
            **public_status(app),
        )
    log.info("reserve: kid=%s held until %.0f", kid, when)
    return web.json_response({"ok": True, "expires_at": when, **public_status(app)})


async def handle(request):
    app = request.app
    route = (request.method, request.path)

    if route == ("GET", "/"):
        return web.Response(
            text=PAGE % {
                "ttl_min": int(RESERVATION_TTL // 60),
                "start": WINDOW_START,
                "end": WINDOW_END,
                "tz": TZ.key,
                "base": str(request.url.origin()),
            },
            content_type="text/html",
        )
    if route == ("GET", "/status"):
        return web.json_response(public_status(app))
    if route in RESERVE:
        return await handle_reserve(request, release=(request.path == "/release"))

    if route not in ALLOWED:
        return problem(404, "not found")

    key = authenticate(request, app["keys"])
    if key is None:
        return problem(401, "missing or invalid bearer token")
    kid = key_id(key)

    if not app["limiter"].allow(kid):
        return problem(429, f"rate limit is {RATE_LIMIT_REQUESTS} requests per minute")

    # Answered above the window gate on purpose: the point of health is to say
    # whether the window is open, which it cannot do if being outside the
    # window is what refuses the request.
    if request.path == "/healthz":
        return web.json_response({"ok": True, "in_window": in_window(), "model": PUBLIC_MODEL})

    if not in_window():
        return problem(
            503, f"outside service hours ({WINDOW_START:02d}:00-{WINDOW_END:02d}:00 {TZ.key})"
        )

    if request.method == "GET":
        return web.json_response({
            "object": "list",
            "data": [{"id": PUBLIC_MODEL, "object": "model", "owned_by": "local"}],
        })

    try:
        body = await request.json()
    except Exception:
        return problem(400, "body is not valid JSON")

    clean, err = sanitise(body)
    if err:
        # 413 for the size case specifically -- it is the one a caller can fix.
        return problem(413 if "limit" in err else 400, err)

    resv = app["reservations"]
    is_reserved = resv.holds(kid)

    started = time.monotonic()
    try:
        await app["slots"].acquire(
            kid, is_reserved, lambda: len(resv.active()), QUEUE_TIMEOUT
        )
    except asyncio.TimeoutError:
        app["demand"].reject()
        held = len(resv.active())
        if is_reserved:
            # Their own slot, so the only way to wait this long is their own
            # earlier request still running. Say so rather than blaming load.
            return problem(503, "your reserved slot is still busy with an earlier request")
        free = app["slots"].general_capacity(held)
        if free == 0 and held:
            return problem(
                503,
                f"all {SLOTS} slot(s) are reserved; reserve one at / to get a "
                f"guaranteed {int(RESERVATION_TTL // 60)}-minute hold",
            )
        return problem(503, f"all {free} unreserved slot(s) busy for over {QUEUE_TIMEOUT:.0f}s")
    waited = time.monotonic() - started

    app["demand"].begin(kid, waited)
    try:
        return await proxy(request, clean, kid, waited)
    finally:
        app["demand"].end()
        await app["slots"].release(kid, is_reserved)


async def proxy(request, body, kid, waited):
    session = request.app["session"]
    started = time.monotonic()
    upstream = f"{OLLAMA}/v1/chat/completions"

    try:
        async with session.post(upstream, json=body) as resp:
            if resp.status != 200:
                # Do not forward ollama's body: it can name local paths and
                # models the caller is not supposed to know about.
                log.warning("kid=%s upstream=%d", kid, resp.status)
                return problem(502, "upstream error")

            out = web.StreamResponse(
                status=200,
                headers={
                    "Content-Type": resp.headers.get("Content-Type", "application/json"),
                    "Cache-Control": "no-store",
                    "X-Accel-Buffering": "no",
                },
            )
            await out.prepare(request)
            total = 0
            async for chunk in resp.content.iter_any():
                total += len(chunk)
                await out.write(chunk)
            await out.write_eof()
            log.info(
                "kid=%s ok wait=%.1fs dur=%.1fs bytes=%d stream=%s",
                kid, waited, time.monotonic() - started, total, bool(body.get("stream")),
            )
            return out
    except asyncio.CancelledError:
        log.info("kid=%s client disconnected after %.1fs", kid, time.monotonic() - started)
        raise
    except Exception as e:
        log.warning("kid=%s upstream failed: %s", kid, type(e).__name__)
        return problem(502, "upstream unreachable")


async def on_startup(app):
    # No total timeout: a 128k prompt spends minutes in prefill before the
    # first token and a whole-request deadline would kill it mid-answer.
    app["session"] = ClientSession(timeout=ClientTimeout(total=None, sock_connect=10))
    app["demand_task"] = asyncio.create_task(demand_writer(app))


async def on_cleanup(app):
    app["demand_task"].cancel()
    try:
        await app["demand_task"]
    except asyncio.CancelledError:
        pass
    await app["session"].close()


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    app = web.Application(client_max_size=64 * 1024 * 1024)
    app["keys"] = load_keys()
    app["limiter"] = RateLimiter()
    app["slots"] = Slots(SLOTS)
    app["demand"] = Demand()
    app["reservations"] = Reservations(RESERVATION_PATH, RESERVATION_TTL)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_route("*", "/{tail:.*}", handle)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, print=None)


if __name__ == "__main__":
    main()
