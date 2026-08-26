#!/usr/bin/env python3
"""Trade context length against slot count based on observed demand.

The card holds one fixed VRAM budget and two things want it: per-slot context
and number of slots. ./llm-proxy.nix has the measured ladder; the short version
is that they trade off, so there is no single right answer -- one caller
wanting 190k and three callers wanting 101k are both reasonable nights.

What makes this awkward is that neither knob is live. llama-server takes
--ctx-size and --parallel at startup and cannot be resized; changing either
means restarting it and loading 16.8 GiB again. So this is not a controller
nudging a dial, it is a thing that decides whether a restart is worth it, and
the answer is usually no. Every rule below exists to make it say no more often:
a cooldown, hysteresis in both directions, and a hard requirement that the
proxy be idle first.

Runs from a timer. Reads the proxy's demand snapshot, writes the environment
file that llama-server and llm-proxy both read, restarts them, verifies the fit
against the card, and reverts if the fit came out worse than predicted.
"""

import json
import os
import subprocess
import sys
import time

DEMAND_PATH = os.environ.get("PROXY_DEMAND_PATH", "/run/llm-proxy/demand.json")
ENV_PATH = os.environ.get("LLM_WINDOW_ENV", "/run/llm-window.env")
STATE_PATH = os.environ.get("LLM_SCALER_STATE", "/var/lib/llm-scaler/state.json")

# [{"ctx": tokens, "slots": n}, ...] most context first. See llm-proxy.nix.
# [{"engine": "ollama"|"llama", "slots": n, "ctx": per_slot_tokens}, ...],
# fewest slots first. The `ctx` is PER SLOT; llama-server takes the total and
# divides it, so the flag it gets is slots * ctx. ollama rows are always one
# slot -- it refuses to batch this architecture -- but decode there is 61 tok/s
# against llama-server's 25, because only ollama drives the model's MTP draft
# head. See the measured table in llm-proxy.nix.
PROFILES = json.loads(os.environ["LLM_PROFILES"])

SERVER_URL = os.environ.get("LLM_SERVER_URL", "http://127.0.0.1:8099")
OLLAMA_URL = os.environ.get("LLM_OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("LLM_OLLAMA_MODEL", "qwen3.8:160k")
VRAM_CEILING_MIB = int(os.environ.get("LLM_VRAM_CEILING_MIB", "23100"))
VRAM_IDLE_CEILING_MIB = int(os.environ.get("LLM_VRAM_IDLE_CEILING_MIB", "200"))

# Do not reload more often than this, whatever demand does. A reload is ~30-60s
# of downtime at these context sizes, so a scaler that flaps costs more service
# than the extra slots it is chasing.
COOLDOWN = float(os.environ.get("LLM_SCALER_COOLDOWN", "1800"))

# Asymmetric on purpose. Adding slots answers callers who are already queueing,
# so it happens on the next tick. Giving slots back (to buy context) costs a
# caller their seat if demand returns, so it waits for a sustained quiet period
# -- an hour of nobody needing the slots, not one quiet tick.
QUIET_BEFORE_RELEASE = float(os.environ.get("LLM_SCALER_QUIET", "3600"))

# Older than this and the snapshot is not evidence of anything. The proxy
# rewrites it every 15s, so a minute of silence means the proxy is gone --
# which is a reason to do nothing, not a reason to conclude "idle, scale down".
STALE_AFTER = 60.0


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def sh(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def vram_used_mib():
    used = 0
    base = "/sys/class/drm"
    for card in os.listdir(base):
        f = os.path.join(base, card, "device", "mem_info_vram_used")
        try:
            with open(f) as fh:
                used = max(used, int(fh.read().strip()) // 1048576)
        except (OSError, ValueError):
            continue
    return used


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_env(profile):
    """One file, every consumer.

    llama-server takes LLM_PARALLEL and the total LLM_CTX_TOTAL; the proxy takes
    its upstream, its model, PROXY_SLOTS and a prompt cap sized to one slot.
    They have to agree: a proxy with more slots than the server just moves the
    queue down into the engine where the wait is invisible, and one with fewer
    wastes a slot the card paid for. Writing all of it from the same place is
    what keeps them from drifting -- and with two engines in play, pointing the
    proxy at the one that is not running is the obvious way to get that wrong.
    """
    tmp = ENV_PATH + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"LLM_PARALLEL={profile['slots']}\n")
        # llama-server divides --ctx-size among slots, so the flag is the total
        # and the per-slot figure is what the ladder is written in.
        f.write(f"LLM_CTX_TOTAL={profile['slots'] * profile['ctx']}\n")
        f.write(f"PROXY_SLOTS={profile['slots']}\n")
        if profile["engine"] == "ollama":
            f.write(f"OLLAMA_URL={OLLAMA_URL}\n")
            # A real tag, because ollama resolves it; llama-server accepts any
            # string and serves whatever it was started with.
            f.write(f"PROXY_MODEL={OLLAMA_MODEL}\n")
        else:
            f.write(f"OLLAMA_URL={SERVER_URL}\n")
            f.write("PROXY_MODEL=qwen3.8\n")
        # Under one slot's context by enough for the reply plus the estimator's
        # error. MAX_OUTPUT_TOKENS is 32000 on the proxy side.
        f.write(f"PROXY_MAX_PROMPT_TOKENS={profile['ctx'] - 38000}\n")
    os.replace(tmp, ENV_PATH)


def ollama_load(keep):
    """keep_alive -1 pins the model; 0 evicts it.

    Eviction is how the card is handed over. Both engines want ~20 GiB and the
    card has 24, so starting one before the other has let go means the second
    fit-checks against a nearly full card and fails -- or worse, squeezes in and
    thrashes.
    """
    return sh("curl", "-sf", "-m", "600", f"{OLLAMA_URL}/api/generate", "-d",
              json.dumps({"model": OLLAMA_MODEL, "prompt": "", "keep_alive": keep}),
              check=False)


def start_ollama():
    sh("systemctl", "stop", "llm-server.service", check=False)
    sh("systemctl", "start", "ollama.service", check=False)
    for _ in range(120):
        if sh("curl", "-sf", f"{OLLAMA_URL}/api/version", check=False).returncode == 0:
            break
        time.sleep(1)
    else:
        log("ollama did not answer in time")
        return False
    return ollama_load(-1).returncode == 0


def start_server():
    """Restart llama-server and wait for it to actually answer.

    /health rather than a TCP connect: llama-server binds the port before the
    weights are on the card, so a connect succeeds minutes before a request
    would. The long ceiling is because loading 16.8 GiB plus up to 328k of KV
    is genuinely slow, and giving up early would read as "does not fit".
    """
    # Evict ollama's copy first -- see ollama_load. This is the only ordering
    # that reliably works when both engines want most of the card.
    ollama_load(0)
    sh("systemctl", "restart", "llm-server.service", check=False)
    for _ in range(600):
        if sh("curl", "-sf", f"{SERVER_URL}/health", check=False).returncode == 0:
            return True
        # ActiveState, not `is-active --quiet`: that returns non-zero for
        # "activating", which is precisely the state a server spends its first
        # several minutes in while it loads 16.8 GiB. Only a terminal state
        # means it is not coming.
        state = sh("systemctl", "show", "llm-server.service", "-p", "ActiveState",
                   "--value", check=False).stdout.strip()
        if state in ("failed", "inactive"):
            log(f"llm-server entered {state} during startup")
            return False
        time.sleep(1)
    log("llm-server did not become healthy in time")
    return False


def apply(profile, state):
    """Switch to this profile, or put back what was there if it does not fit.

    The verification is against the card rather than against the server's own
    fit check. llama.cpp's check is honest -- it declines outright when a
    profile does not fit, which is why probing the ladder was survivable at all
    -- but it warns and proceeds in the marginal band, and it is exactly that
    band the ceiling is set to exclude.
    """
    previous = state.get("profile")
    write_env(profile)
    healthy = start_ollama() if profile["engine"] == "ollama" else start_server()

    loaded = vram_used_mib()
    if not healthy or loaded > VRAM_CEILING_MIB:
        why = "did not start" if not healthy else f"loaded at {loaded} MiB, over {VRAM_CEILING_MIB}"
        log(f"profile {profile} {why} -- reverting")
        if previous:
            write_env(previous)
            start_ollama() if previous["engine"] == "ollama" else start_server()
        else:
            if os.path.exists(ENV_PATH):
                os.unlink(ENV_PATH)
            start_server()
            sh("systemctl", "restart", "llm-proxy.service", check=False)
        # Remember the failure so the next tick does not walk straight back
        # into it. This is the only durable record that a profile the table
        # claims fits, does not.
        bad = state.setdefault("too_big", [])
        key = [profile["engine"], profile["ctx"]]
        if key not in bad:
            bad.append(key)
        return False

    log(f"profile engine={profile['engine']} slots={profile['slots']} "
        f"ctx={profile['ctx']} loaded, card at {loaded} MiB")
    state["profile"] = profile
    state["changed_at"] = time.time()
    # Restart the proxy last, so it comes up already pointing at a model that
    # is loaded and verified rather than at one still being allocated.
    sh("systemctl", "restart", "llm-proxy.service", check=False)
    return True


def choose(want, state):
    """Most context that still gives every concurrent caller a slot.

    PROFILES runs most-context-first, so the first row with enough slots is the
    one that gives up the least context to get them.
    """
    # Keyed by (engine, ctx): the same context on the two engines is not the
    # same allocation, so a row that did not fit on one says nothing about the
    # other.
    too_big = {tuple(x) for x in state.get("too_big", [])}
    usable = [p for p in PROFILES if (p["engine"], p["ctx"]) not in too_big]
    if not usable:
        return None
    for p in usable:
        if p["slots"] >= want:
            return p
    return usable[-1]


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_PATH)


def initial():
    """Open the window on the first rung: ollama, one slot, 61 tok/s.

    Same code path as every later change, deliberately -- the load-and-verify
    step is the one that can wedge the card, and having a second copy of it in
    a shell script for the 03:00 case is how the two drift apart.

    Starts at the top of the ladder rather than guessing the night's demand: a
    caller who arrives alone gets the fast engine, and the scaler trades speed
    for slots only once there is somebody to trade it for.
    """
    state = read_json(STATE_PATH, default={}) or {}
    # Forget which profiles were too big. That verdict was reached against
    # whatever else held the card that night; with the compositor down this
    # time it may not hold, and the load-and-verify below is what re-decides.
    state.pop("too_big", None)

    used = vram_used_mib()
    if used > VRAM_IDLE_CEILING_MIB:
        log(f"card holds {used} MiB (ceiling {VRAM_IDLE_CEILING_MIB}); compositor still up "
            f"or VRAM wedged -- staying single-slot")
        if os.path.exists(ENV_PATH):
            os.unlink(ENV_PATH)
        sh("systemctl", "restart", "llm-proxy.service", check=False)
        return 0

    ok = apply(PROFILES[0], state)
    save_state(state)
    return 0 if ok else 1


def main():
    if os.environ.get("LLM_SCALER_INITIAL") == "1":
        return initial()

    demand = read_json(DEMAND_PATH)
    if not demand:
        log("no demand snapshot -- proxy down or never started; doing nothing")
        return 0
    age = time.time() - demand.get("ts", 0)
    if age > STALE_AFTER:
        log(f"demand snapshot is {age:.0f}s stale -- doing nothing")
        return 0

    state = read_json(STATE_PATH, default={}) or {}
    current = state.get("profile")

    # Never reload under a caller. Everything below assumes we can afford to
    # take the model away for a minute, and that is only true at zero in-flight.
    if demand.get("active", 0) > 0:
        log(f"{demand['active']} request(s) in flight -- deferring")
        return 0

    # And never under a reservation. A restart is a minute of downtime, which
    # is exactly what somebody accepted a 30-minute hold in order to avoid --
    # honouring the hold has to outrank picking a better profile. This is also
    # why reservation_denials exists: people turned away while the profile is
    # frozen leave no other trace, and they are the evidence that decides the
    # next change once the last hold lapses.
    held = demand.get("reserved", 0)
    denials = demand.get("reservation_denials", 0)
    if held:
        until = demand.get("reserved_until", 0)
        mins = max(0, (until - time.time()) / 60)
        current_slots = (current or PROFILES[0])["slots"]
        can_grow = any(p["slots"] > current_slots for p in PROFILES)
        # The one exception to honouring a hold. On the one-slot ollama rung a
        # single reservation is the entire service, so without this the holder
        # locks everybody else out for thirty minutes AND freezes the profile
        # that would have made room for them -- the scaler cannot fix the
        # problem precisely when the problem exists.
        #
        # Upshifting costs the holder about a minute of restart. It does not
        # cost them the reservation: holds are persisted and reload on start,
        # which is what makes this a pause rather than an eviction. A minute of
        # interruption for one person beats a hard lockout for everyone else.
        if not (denials and can_grow):
            log(f"{held} reservation(s) active, last lapses in {mins:.0f}m -- holding profile")
            return 0
        log(f"{held} reservation(s) active but {denials} turned away and a wider "
            f"profile exists -- upshifting through the hold")

    since_change = time.time() - state.get("changed_at", 0)
    if since_change < COOLDOWN:
        log(f"last change {since_change:.0f}s ago, cooldown {COOLDOWN:.0f}s -- deferring")
        return 0

    peak = demand.get("peak_concurrency", 0)

    # One slot of headroom above observed peak: the peak is a rear-view number
    # and the cost of being one short is a caller queueing for QUEUE_TIMEOUT.
    want = peak + 1

    # Queueing and rejections are callers who wanted a slot and did not get
    # one, so they are demand the peak could not record -- peak counts requests
    # that got in. One rung at a time on that evidence, though: jumping two
    # would trade away more context than the queue proves is needed.
    pressure = (
        demand.get("queued_requests", 0)
        + demand.get("rejects", 0)
        + demand.get("reservation_denials", 0)
    )
    if pressure and current:
        want = max(want, current["slots"] + 1)

    target = choose(want, state)
    if target is None:
        log("every profile is marked too big -- nothing to do")
        return 1

    if current == target:
        return 0

    # Having decided a hold may be interrupted, only ever interrupt it to make
    # room. Trading slots away underneath a reservation is the eviction this is
    # trying not to be.
    if held and current and target["slots"] <= current["slots"]:
        log(f"{held} reservation(s) active and {target['slots']} slots is no wider -- holding")
        return 0

    # Downshift (fewer slots, more context) only after a sustained quiet spell.
    # Upshift on the next tick, because those callers are queueing now.
    if current and target["slots"] < current["slots"]:
        if since_change < QUIET_BEFORE_RELEASE or pressure:
            log(f"quiet for {since_change:.0f}s, want {QUIET_BEFORE_RELEASE:.0f}s -- holding")
            return 0

    log(f"peak={peak} want={want} pressure={pressure}: {current} -> {target}")
    ok = apply(target, state)
    save_state(state)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
