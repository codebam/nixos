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

# Held under the model's real 160k window so there is room for the reply. The
# count is an estimate (see estimate_tokens); the margin absorbs its error.
MAX_PROMPT_TOKENS = int(os.environ.get("PROXY_MAX_PROMPT_TOKENS", "120000"))
MAX_OUTPUT_TOKENS = int(os.environ.get("PROXY_MAX_OUTPUT_TOKENS", "8192"))

# One request at a time, because that is what the card is. OLLAMA_NUM_PARALLEL
# is 1 and a second caller would queue inside ollama anyway -- queueing here
# instead means the wait is visible and bounded rather than a silent stall.
SLOTS = int(os.environ.get("PROXY_SLOTS", "1"))
QUEUE_TIMEOUT = float(os.environ.get("PROXY_QUEUE_TIMEOUT", "300"))

RATE_LIMIT_REQUESTS = int(os.environ.get("PROXY_RATE_LIMIT", "60"))
RATE_LIMIT_WINDOW = 60.0

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


# --- handlers --------------------------------------------------------------


def problem(status, message, **extra):
    return web.json_response({"error": {"message": message, "type": "proxy_error", **extra}}, status=status)


async def handle(request):
    app = request.app
    route = (request.method, request.path)
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
        return web.json_response({"ok": True, "in_window": in_window(), "model": MODEL})

    if not in_window():
        return problem(
            503, f"outside service hours ({WINDOW_START:02d}:00-{WINDOW_END:02d}:00 {TZ.key})"
        )

    if request.method == "GET":
        return web.json_response({
            "object": "list",
            "data": [{"id": MODEL, "object": "model", "owned_by": "local"}],
        })

    try:
        body = await request.json()
    except Exception:
        return problem(400, "body is not valid JSON")

    clean, err = sanitise(body)
    if err:
        # 413 for the size case specifically -- it is the one a caller can fix.
        return problem(413 if "limit" in err else 400, err)

    started = time.monotonic()
    try:
        await asyncio.wait_for(app["slots"].acquire(), timeout=QUEUE_TIMEOUT)
    except asyncio.TimeoutError:
        return problem(503, f"all {SLOTS} slot(s) busy for over {QUEUE_TIMEOUT:.0f}s")
    waited = time.monotonic() - started

    try:
        return await proxy(request, clean, kid, waited)
    finally:
        app["slots"].release()


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


async def on_cleanup(app):
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
    app["slots"] = asyncio.Semaphore(SLOTS)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_route("*", "/{tail:.*}", handle)
    web.run_app(app, host=LISTEN_HOST, port=LISTEN_PORT, print=None)


if __name__ == "__main__":
    main()
