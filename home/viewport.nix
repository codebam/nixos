{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  # Which screen the user is on, as "name x y scale", or nothing.
  #
  # The sway config gets this from `swaymsg -t get_outputs`; Viewport has no
  # such command, so this asks the control socket directly. `output.query` is
  # answered with the whole layout and the active output flagged -- the shell
  # tracks which that is, because it follows the pointer and the keyboard.
  #
  # Prints nothing when the compositor does not report an active output, which
  # is what a session older than that field does. Every caller has to cope.
  # Read rather than piped through socat: the socket is a broadcast stream that
  # stays open after the answer, so a pipeline can only stop on an idle timeout
  # -- a second of waiting before the screen is frozen, which is a second of the
  # screen changing.
  activeOutput = pkgs.writeScript "viewport-active-output" ''
    #!${pkgs.python3}/bin/python3
    import json, os, socket, sys

    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    display = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
    path = os.path.join(runtime, "viewport-%s.sock" % display)

    # Any failure at all means "no active output": the caller has a path for
    # that, and a screenshot binding that raises a traceback is worse than one
    # that falls back.
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1.0)
        sock.connect(path)
        sock.sendall(b'{"type":"output.query"}\n')
        buffered = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buffered += chunk
            while b"\n" in buffered:
                line, buffered = buffered.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if message.get("type") != "output.layout":
                    continue
                # The layout has arrived; there is no second answer to wait for.
                for output in message.get("outputs", []):
                    if output.get("active"):
                        print("%s %d %d %s" % (output["name"], output["x"],
                                               output["y"], output["scale"]))
                        sys.exit(0)
                sys.exit(0)
    except Exception:
        pass
  '';

  screenshot = pkgs.writeShellScript "screenshot" ''
    set -euo pipefail
    shots="$HOME/Pictures/Screenshots"
    mkdir -p "$shots"
    out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
    # The screen being looked at, not every screen joined into one wide image
    # -- which is what a bare `grim` writes on two monitors.
    read -r focused _ _ _ < <(${activeOutput}) || true
    if [ -n "''${focused:-}" ]; then
      ${pkgs.grim}/bin/grim -o "$focused" "$out"
    else
      ${pkgs.grim}/bin/grim "$out"
    fi
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$out"
  '';

  # Freeze the screen, then crop the frozen copy: a menu that closes when it
  # loses the pointer is still in the picture, which is the whole point of
  # grabbing before selecting.
  #
  # The freeze has to be one output. `grim` with no `-o` writes the entire
  # layout, so on two monitors `imv -f` was showing both of them shrunk into
  # one fullscreen window on one screen -- and the coordinates slurp reported
  # described the desktop, not that picture.
  #
  # The crop then discarded the selection anyway: slurp prints "X,Y WxH" and
  # ImageMagick's -crop wants "WxH+X+Y". It does not reject the other
  # spelling, it ignores it, so every selection saved and copied the untouched
  # two-monitor grab.
  screenshotSelect = pkgs.writeShellScript "screenshot-select" ''
    set -euo pipefail
    shots="$HOME/Pictures/Screenshots"
    mkdir -p "$shots"

    read -r focused ox oy scale < <(${activeOutput}) || true
    if [ -z "''${focused:-}" ]; then
      # No active output to freeze. Selecting on the live desktop and letting
      # grim cut the region out of the layout is still right, it just cannot
      # hold the screen still while the selection is made.
      region=$(${pkgs.slurp}/bin/slurp) || exit 0
      [ -n "$region" ] || exit 0
      out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
      ${pkgs.grim}/bin/grim -g "$region" "$out"
      ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$out"
      exit 0
    fi

    temp_file=$(mktemp -t screenshot-XXXXXX.png)
    imv_pid=""
    cleanup() {
      [ -n "$imv_pid" ] && kill "$imv_pid" 2>/dev/null || true
      rm -f "$temp_file"
    }
    trap cleanup EXIT

    ${pkgs.grim}/bin/grim -o "$focused" "$temp_file"
    ${pkgs.imv}/bin/imv -f "$temp_file" &
    imv_pid=$!
    sleep 0.2
    region=$(${pkgs.slurp}/bin/slurp -o "$focused") || exit 0
    [ -n "$region" ] || exit 0

    # slurp answers in the layout's own coordinates and the frozen file is one
    # output's pixels: shift by the output's origin, and multiply by its scale,
    # which is the factor between the two. A 1.5x monitor selected 400 wide is
    # 600 pixels of the file.
    pos=''${region%% *}
    size=''${region##* }
    read -r cx cy cw ch < <(
      ${pkgs.gawk}/bin/awk -v x="''${pos%%,*}" -v y="''${pos##*,}" \
        -v w="''${size%%x*}" -v h="''${size##*x}" \
        -v ox="$ox" -v oy="$oy" -v s="$scale" \
        'BEGIN { printf "%d %d %d %d\n",
                   int((x - ox) * s + 0.5), int((y - oy) * s + 0.5),
                   int(w * s + 0.5), int(h * s + 0.5) }'
    )

    out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
    ${pkgs.imagemagick}/bin/magick "$temp_file" \
      -crop "''${cw}x''${ch}+''${cx}+''${cy}" +repage "$out"
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$out"
  '';
in
{
  # Viewport's bootstrap config: the tier that has to keep working when the web
  # shell does not. The shell is fetched at startup, and if it fails to load
  # anything it owned dies with it — a binding defined here still works in that
  # state, which is the difference between a broken desktop and a machine you
  # cannot quit without switching to a TTY.
  xdg.configFile."viewport/config.json".text = builtins.toJSON {
    layout = "scrolling";

    # What Mod4+Return opens. Without it the compositor falls back to its
    # built-in default, which is foot.
    terminal = "rio";

    outputs = {
      "*" = {
        max_refresh = true;
      };
    };

    adaptive_sync = true;
    bar = "auto";
    logo = false;
    tutorial = false;

    # Space around and between windows, in pixels. `inner` is the gap between
    # adjacent windows; `outer` is extra space around the edge of the output,
    # added on top of the inner gap. `smart` drops the inner gap on a single
    # window. Every layout model reads the same values, so a few numbers space
    # the whole desktop.
    gaps = {
      inner = 15;
      smart = true;
    };

    # No theme block, deliberately. Every key here is written straight onto
    # the document as a CSS custom property (`applyTheme`, data/shell/
    # windows.js), so overriding them replaces whatever shell.css does with
    # those tokens. Flattening bg and the glows to black and transparent meant
    # the wallpaper vignette, the elevation shadows and the workspace-pill glow
    # all resolved to black-on-black or nothing at all — the styling was
    # applying and had nothing to show for it.

    idle = {
      lock_after = 600;
      lock_command = "${lib.getExe pkgs.swaylock} -f";
      blank_after = 900;
    };

    # binds_override appends/overrides keybindings on top of built-in defaults
    # without suppressing the default keymap.
    binds_override = {
      "Mod4+x" = "exec ${screenshotSelect}";
      "Mod4+Shift+x" = "exec ${screenshot}";
      "Print" = "exec ${screenshot}";
    }
    # Press to start dictating, press again to stop and have it typed. Not
    # `Mod4+v`, which the built-in keymap already spends on splitting the next
    # window vertically. The host has to have the engine installed for this to
    # be worth binding: the Steam Deck imports this file too and does not.
    // lib.optionalAttrs (osConfig.voiceToText.enable or false) {
      "Mod4+Shift+v" = "exec ${lib.getExe osConfig.voiceToText.package}";
    };
  };
}
