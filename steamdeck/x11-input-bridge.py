#!/usr/bin/env python3
"""Mirror XTEST input from Xwayland into uinput devices the compositor reads.

Why this exists on the Deck: Steam Input delivers the back-button chords (and
Steam's trackpad mouse) as XTEST events inside Xwayland. A rootless Xwayland
never hands synthetic input back to the Wayland compositor, so the chords
reached no binding and the pointer never reached a seat -- the session showed
no cursor at all. This process watches the X server's own key state (and
pointer) at a high rate and re-emits everything the kernel did not already
see (i.e. synthetic input) through two virtual devices: a keyboard and a
mouse. Keys are emitted modifiers-first so a chord (Alt+R, Alt+Shift+Q, ...)
forms for the compositor's binding matcher; the pointer becomes relative
motion plus button events.

Device id 28de:125a is deliberate: vendor 28de (Valve) because the Deck's
udev rules tag Valve-vendor input devices for the seat (the rule matches on
vendor only, so any product id keeps the seat access); product 0x125a chosen
to be novel because 0x1205 IS the Deck controller's own id -- Steam claims
its own hardware, and a bridge impersonating the controller id is the kind
of collision that blocks input when the Steam UI enumerates devices.

Usage: x11-input-bridge.py [x-socket] [log-file] [debug]
"""
import socket, struct, os, sys, time, array, fcntl, re

SOCK = sys.argv[1] if len(sys.argv) > 1 else None  # optional preferred socket
LOG = sys.argv[2] if len(sys.argv) > 2 else '/tmp/vpinput/bridge.log'
DEBUG = len(sys.argv) > 3 and sys.argv[3] == 'debug'

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y = 0, 1
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
MODIFIERS = {29, 97, 42, 54, 56, 100, 125, 126}  # ctrl/shift/alt/meta both sides
# System control keys: systemd-logind turns KEY_POWER/KEY_SUSPEND/KEY_SLEEP/...
# events from ANY input device into suspend/hibernate actions, so a synthetic
# XF86Suspend relayed through here can sleep the machine mid-session (seen on
# the Deck: phantom suspends while the launcher was open -- logind logged
# "Suspend key pressed short" with nobody touching the power button). Never
# mirror these keys, and never advertise their keybits, so logind has no
# reason to treat this device as a power button at all.
DENY_KEYS = {116, 142, 143, 205, 206, 248}  # POWER SLEEP WAKEUP SUSPEND POWER2 HIBERNATE
DENIED_LOGGED: set = set()
# Keys the controller's desktop layout can actually send (the layout's own
# key_press list): the four back-button chords (Alt+R, Alt+D, Alt+Shift+Q,
# Alt+Tab), the pad buttons that fake Esc/Enter/Space/arrows, F8, modifiers.
# Xwayland re-applies its keymap (session start) and Steam churns its
# controller configs (live previews) by dragging a machine-generated key
# carousel across the whole keycode space; without this gate the bridge
# mirrors that noise too -- volume, brightness, menu and calculator keys
# landing in whatever is focused -- and the rolling edges of the carousel
# slip under the mass-change resync. Anything not in this set is churn.
ALLOW_KEYS = {
    1,    # ESC
    15,   # TAB
    16,   # Q
    19,   # R
    28,   # ENTER
    29,   # LEFT_CTRL
    32,   # D
    42,   # LEFT_SHIFT
    56,   # LEFT_ALT
    57,   # SPACE
    66,   # F8
    103,  # UP
    105,  # LEFT
    106,  # RIGHT
    108,  # DOWN
}
DROPPED_LOGGED: set = set()

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_DEV_SETUP = 0x405c5503
UI_DEV_CREATE = 0x5501

LAST_MOTION_LOG = [0.0]
REAL_KBD: list = [None]  # resolved lazily from /proc/bus/input/devices


def log(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, 'a') as f:
            f.write('%s %s\n' % (time.strftime('%H:%M:%S'), msg))
    except Exception:
        pass


def read_exact(s, n):
    b = b''
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise EOFError('closed')
        b += c
    return b


def drain(s, wait=0.35):
    s.settimeout(wait)
    data = b''
    try:
        while True:
            c = s.recv(4096)
            if not c:
                break
            data += c
    except Exception:
        pass
    return data


def find_real_kbd():
    """the event node of the physical AT keyboard, by name (numbers drift)"""
    try:
        with open('/proc/bus/input/devices') as f:
            for block in f.read().split('\n\n'):
                if 'AT Translated Set 2 keyboard' in block:
                    m = re.search(r'event(\d+)', block)
                    if m:
                        return '/dev/input/event%s' % m.group(1)
    except Exception:
        pass
    return None


def make_uinput(name, rel=False):
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    if rel:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
        fcntl.ioctl(fd, UI_SET_RELBIT, REL_X)
        fcntl.ioctl(fd, UI_SET_RELBIT, REL_Y)
        for code in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
            fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    else:
        i = 1
        while i < 249:
            if i not in DENY_KEYS:
                try:
                    fcntl.ioctl(fd, UI_SET_KEYBIT, i)
                except Exception:
                    pass
            i += 1
    nm = name.encode() + b'\0' * (80 - len(name))
    setup = struct.pack('<HHHH', 0x0003, 0x28de, 0x125a, 1) + nm + struct.pack('<I', 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def ev(fd, etype, code, value):
    now = time.time()
    sec = int(now)
    usec = int((now - sec) * 1e6)
    os.write(fd, struct.pack('<qqHHi', sec, usec, etype, code, value))


def emit_key(fd, code, value):
    ev(fd, EV_KEY, code, value)
    ev(fd, EV_SYN, 0, 0)


def real_key_state():
    """evdev keycodes currently down on the physical keyboard"""
    if REAL_KBD[0] is None:
        REAL_KBD[0] = find_real_kbd()
    if REAL_KBD[0] is None:
        return set()
    buf = array.array('B', [0] * 96)
    try:
        fd = os.open(REAL_KBD[0], os.O_RDONLY | os.O_NONBLOCK)
        req = 0x80000000 | (96 << 16) | (0x45 << 8) | 0x18  # EVIOCGKEY
        fcntl.ioctl(fd, req, buf, True)
        os.close(fd)
    except Exception:
        REAL_KBD[0] = None  # re-resolve next time
        return set()
    out = set()
    i = 0
    while i < 96 * 8:
        b, r = divmod(i, 8)
        if (buf[b] >> r) % 2:
            out.add(i)
        i += 1
    return out


def connect_x():
    # Xwayland's display number increments on every session restart (:0, :1,
    # :2, ...) and dead sockets stay behind in /tmp/.X11-unix, so a hardcoded
    # X0 ends up retrying a stale socket forever. Try the explicit socket
    # first when given, then every candidate; the live one answers the setup
    # handshake.
    cands: list = []
    if SOCK:
        cands.append(SOCK)
    try:
        for f in sorted(os.listdir('/tmp/.X11-unix')):
            if f.startswith('X') and f[1:].isdigit():
                p = '/tmp/.X11-unix/' + f
                if p not in cands:
                    cands.append(p)
    except Exception:
        pass
    if not cands:
        cands = ['/tmp/.X11-unix/X0']
    last = None
    for path in cands:
        try:
            return try_connect(path)
        except Exception as e:
            last = e
            continue
    raise last if last else RuntimeError('no X socket answered')


def try_connect(path):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3)
    s.connect(path)
    s.settimeout(None)
    req = struct.pack('<BBHHHH', 0x6c, 0, 11, 0, 0, 0) + struct.pack('<H', 0)
    s.send(req)
    hdr = read_exact(s, 8)
    if hdr[0] != 1:
        raise ValueError('X connect refused')
    extra = int.from_bytes(hdr[6:8], 'little') * 4
    body = read_exact(s, extra)
    # Find the screen's root window: width/height fields sit 20 bytes after
    # the screen's root window id in the setup body. The reply length is
    # taken from a live query (Xwayland's QueryPointer reply carries four
    # trailing bytes past the spec size).
    root, ptr_size = None, None
    for pat in (struct.pack('<HH', 1280, 800), struct.pack('<HH', 800, 1280),
                struct.pack('<HH', 1280, 720), struct.pack('<HH', 1920, 1080),
                struct.pack('<HH', 1024, 768), struct.pack('<HH', 640, 480)):
        for m in re.finditer(re.escape(pat), body):
            cand = struct.unpack('<I', body[m.start() - 20:m.start() - 16])[0]
            if cand < 256:
                continue
            s.send(struct.pack('<BBHI', 38, 0, 2, cand))
            data = drain(s, 0.3)
            if len(data) >= 28 and data[0] == 1:
                rx, ry = struct.unpack('<hh', data[16:20])
                if 0 <= rx <= 8192 and 0 <= ry <= 8192:
                    root, ptr_size = cand, len(data)
                    break
        if root:
            break
    log('connected: root=%s ptr_reply=%s' % (hex(root) if root else 'none', ptr_size))
    return s, root, ptr_size


def query_keymap(s):
    s.send(struct.pack('<BBH', 44, 0, 1))
    read_exact(s, 8)
    raw = read_exact(s, 32)
    v = 0
    i = 0
    while i < 32:
        v |= raw[i] << (8 * i)
        i += 1
    return v


def query_pointer(s, root, ptr_size):
    s.send(struct.pack('<BBHI', 38, 0, 2, root))
    read_exact(s, 8)
    return read_exact(s, ptr_size - 8)


def main():
    kbd = make_uinput('viewport-x11-bridge', rel=False)
    mouse = make_uinput('viewport-x11-bridge-mouse', rel=True)
    log('uinput devices created')
    time.sleep(6)  # let the seat hand us an ACL before anyone needs it
    while True:
        try:
            xs, root, ptr_size = connect_x()
            break
        except Exception as e:
            log('waiting for X at %s: %r' % (SOCK, e))
            time.sleep(3)
    prev = query_keymap(xs)
    prev_pos = None
    prev_mask = 0
    prev_body = [b'']
    log('bridge up prev=%064x' % prev)
    loops = 0
    while True:
        try:
            cur = query_keymap(xs)
            loops += 1
            if loops % 2000 == 0:
                log('hb %064x keys' % cur)
            if cur != prev:
                real = real_key_state()
                # A keymap swap -- Xwayland reconfiguring the keyboard at
                # session start, Steam grabbing the controller -- flips dozens
                # of state bits at once, and mirroring that reads as a phantom
                # flood of keypresses: it fires calculator/WWW/file-manager
                # action keys and browser shortcuts in whatever is focused
                # ("pressing a back button opened random apps"). Real input
                # never changes more than a few keys in one poll, so treat a
                # mass change as a resync instead of as input.
                changed = bin(cur ^ prev).count('1')
                if changed > 10:
                    log('resync: %d key state bits changed at once (keymap swap?)' % changed)
                    prev = cur
                    continue
                downs, ups = [], []
                i = 8
                while i < 256:
                    if ((cur >> i) % 2) != ((prev >> i) % 2):
                        code = i - 8
                        if code in DENY_KEYS:
                            if code not in DENIED_LOGGED:
                                DENIED_LOGGED.add(code)
                                log('refusing to mirror system key code=%d' % code)
                        elif code not in ALLOW_KEYS:
                            if code not in DROPPED_LOGGED:
                                DROPPED_LOGGED.add(code)
                                log('dropping non-controller key code=%d (machine churn)' % code)
                        elif code in real:
                            pass  # a real key: the compositor already saw it
                        elif (cur >> i) % 2:
                            downs.append(code)
                        else:
                            ups.append(code)
                    i += 1
                # modifiers first on the way down, last on the way up
                downs.sort(key=lambda c: 0 if c in MODIFIERS else 1)
                ups.sort(key=lambda c: 1 if c in MODIFIERS else 0)
                for code, value, what in [(c, 1, 'down') for c in downs] + [(c, 0, 'up') for c in ups]:
                    try:
                        emit_key(kbd, code, value)
                        log('mirror %s code=%d val=%d' % (what, code, value))
                    except Exception as e3:
                        log('emit failed code=%d: %r' % (code, e3))
                prev = cur
            if root and loops % 2 == 0:
                body = query_pointer(xs, root, ptr_size)
                rx, ry = struct.unpack('<hh', body[8:12])
                mask = struct.unpack('<H', body[16:18])[0]
                if body != prev_body[0]:
                    if DEBUG:
                        log('ptr_raw %s (rx=%d ry=%d mask=%04x)' % (body.hex(), rx, ry, mask))
                    prev_body[0] = body
                if prev_pos is None:
                    prev_pos = (rx, ry)
                    prev_mask = mask
                else:
                    dx, dy = rx - prev_pos[0], ry - prev_pos[1]
                    if dx or dy:
                        if abs(dx) <= 300 and abs(dy) <= 300:
                            ev(mouse, EV_REL, REL_X, dx)
                            ev(mouse, EV_REL, REL_Y, dy)
                            ev(mouse, EV_SYN, 0, 0)
                            if time.time() - LAST_MOTION_LOG[0] > 1.0:
                                LAST_MOTION_LOG[0] = time.time()
                                log('motion %d %d (at %d,%d)' % (dx, dy, rx, ry))
                        prev_pos = (rx, ry)
                    if mask != prev_mask:
                        for bit, code in ((0x100, BTN_LEFT), (0x200, BTN_RIGHT), (0x400, BTN_MIDDLE)):
                            was = 1 if prev_mask % (bit * 2) >= bit else 0
                            now = 1 if mask % (bit * 2) >= bit else 0
                            if was != now:
                                emit_key(mouse, code, now)
                                log('mirror mouse %s' % ('down' if now else 'up'))
                        prev_mask = mask
        except Exception as e:
            log('error: %r' % e)
            try:
                xs.close()
            except Exception:
                pass
            time.sleep(2)
            while True:
                try:
                    xs, root, ptr_size = connect_x()
                    prev = query_keymap(xs)
                    prev_pos = None
                    break
                except Exception as e2:
                    log('reconnect failed: %r' % e2)
                    time.sleep(3)
        time.sleep(0.002)


if __name__ == '__main__':
    main()
