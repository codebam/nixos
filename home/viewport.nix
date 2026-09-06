{
  config,
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

  # The notification sound: a dog bark, one of the four alert sounds GNOME 2
  # shipped. GNOME dropped the chooser and the files with it; MATE, being that
  # desktop's fork, is what still carries them. The freedesktop sound theme --
  # the one every distribution installs -- has no equivalent, which is why this
  # is not simply a `sound_name`.
  #
  # The file alone, not the package holding it. mate-media is a mixer
  # application: 1.3G of closure, GTK and all, to carry 13kB of ogg. Copying it
  # out means the sound is in the runtime closure and the mixer is not.
  bark = pkgs.runCommand "bark.ogg" { } ''
    cp ${pkgs.mate-media}/share/sounds/mate/default/alerts/bark.ogg $out
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
    # Bare, deliberately. `slurp -o "$focused"` reads as "select on this
    # output" and is nothing of the kind: -o takes no argument -- it adds a
    # snap rectangle for every output -- and the name was a positional
    # argument slurp ignores. The selection was never held to the frozen
    # output while the crop below assumed it was, so a drag on the other
    # monitor cropped a region that is not in the file: ImageMagick warns
    # "geometry does not contain image", writes a 1x1 PNG, and exits 0, which
    # `set -e` cannot see. A selection spanning both monitors was truncated at
    # the edge just as quietly.
    region=$(${pkgs.slurp}/bin/slurp) || exit 0
    [ -n "$region" ] || exit 0

    # The frozen file's own size, which is what the selection has to fall
    # inside. Read from the file rather than assumed from the mode: the output
    # is captured at its transform and scale, and this is the picture that
    # exists.
    # The newline is not decoration: `identify` writes the format string and
    # nothing else, and `read` reports failure at an EOF it did not reach
    # through one -- which under `set -e` is the whole script, two lines after
    # the screen was frozen.
    read -r fw fh < <(
      ${pkgs.imagemagick}/bin/magick identify -format "%w %h\n" "$temp_file"
    )

    # slurp answers in the layout's own coordinates and the frozen file is one
    # output's pixels: shift by the output's origin, and multiply by its scale,
    # which is the factor between the two. A 1.5x monitor selected 400 wide is
    # 600 pixels of the file.
    #
    # Unless the selection is not on that output at all, or hangs over its
    # edge -- both of which are ordinary on two monitors, because only the
    # focused one is frozen and the other is still live and still selectable.
    # Then there is no crop of this file that answers, and awk says so.
    pos=''${region%% *}
    size=''${region##* }
    read -r mode cx cy cw ch < <(
      ${pkgs.gawk}/bin/awk -v x="''${pos%%,*}" -v y="''${pos##*,}" \
        -v w="''${size%%x*}" -v h="''${size##*x}" \
        -v ox="$ox" -v oy="$oy" -v s="$scale" -v fw="$fw" -v fh="$fh" \
        'BEGIN {
           inside = (x >= ox && y >= oy &&
                     (x + w) <= ox + fw / s && (y + h) <= oy + fh / s)
           if (!inside) { print "live 0 0 0 0"; exit }
           printf "crop %d %d %d %d\n",
                    int((x - ox) * s + 0.5), int((y - oy) * s + 0.5),
                    int(w * s + 0.5), int(h * s + 0.5) }'
    )

    out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
    if [ "$mode" = crop ]; then
      ${pkgs.imagemagick}/bin/magick "$temp_file" \
        -crop "''${cw}x''${ch}+''${cx}+''${cy}" +repage "$out"
    else
      # Off the frozen output, so cut it out of the live desktop instead: the
      # pixels are right, they were simply not held still while the selection
      # was made. Better than a screenshot of one pixel.
      ${pkgs.grim}/bin/grim -g "$region" "$out"
    fi
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
    rules = [
      # Don't capture OBS Studio
      {
        app_id = "com.obsproject.Studio";
        capture = false;
      }
      # Don't capture chromium
      {
        app_id = "chromium-browser";
        capture = false;
      }
    ];

    # What Mod4+Return opens. Without it the compositor falls back to its
    # built-in default, which is foot.
    terminal = "rio";

    # The desktop background, taken from stylix so that the picture the rest of
    # the session is themed against is the one the compositor draws. Stylix has
    # no target for this compositor and never will set it by itself, so this is
    # the wiring: without these two lines the shell paints its own gradient and
    # `stylix.image` reaches nothing.
    #
    # The fitting names are stylix's own -- viewport takes `fill`, `fit`,
    # `stretch`, `center` and `tile`, which is `imageScalingMode` exactly -- so
    # this is handed across rather than translated.
    wallpaper = "${osConfig.stylix.image}";
    wallpaper_mode = osConfig.stylix.imageScalingMode;

    outputs = {
      "*" = {
        max_refresh = true;
      };
    };

    # What a notification sounds like when the program sending it does not ask
    # for something else. Viewport holds org.freedesktop.Notifications itself,
    # so this is the setting a mako or dunst config would carry -- there is no
    # notification daemon here to configure instead. A sender's own `sound-file`
    # or `sound-name` hint wins over this, and `suppress-sound` silences it.
    notifications = {
      sound_file = "${bark}";
    };

    adaptive_sync = true;
    bar = "auto";
    logo = false;
    tutorial = false;

    # Override the whole right side of the bar with an explicit, ordered list.
    # A bare string is a built-in module (net, disk, cpu, load, memory, clock,
    # mode); an object is a widget, as bar_widgets used to take. The layout:
    # volume far left, then the Pickering weather, network, the root disk with
    # the /games watcher right after it, and the rest of the modules.
    bar_items = [
      { type = "volume"; }
      { type = "mic"; }
      {
        type = "weather";
        location = "Pickering, ON, Canada";
      }
      "net"
      "disk"
      {
        type = "disk";
        path = "/games";
      }
      "cpu"
      "load"
      "memory"
      "clock"
    ];

    # Space around and between windows, in pixels. `inner` is the gap between
    # adjacent windows; `outer` is extra space around the edge of the output,
    # added on top of the inner gap. `smart` drops the inner gap on a single
    # window. Every layout model reads the same values, so a few numbers space
    # the whole desktop.
    gaps = {
      inner = 15;
      smart = true;
    };

    # The frame around a window. `radius` is the corner in pixels, on the
    # outside of the border, and `width` is how thick that border is. Both are
    # read by the compositor as well as the shell: a window's contents are a
    # surface the compositor draws, so it crops each client to the same corner
    # the page drew — square here, which costs it nothing.
    border = {
      radius = 0;
      width = 2;
    };

    # No theme block, deliberately. Every key here is written straight onto
    # the document as a CSS custom property (`applyTheme`, data/shell/
    # windows.js), so overriding them replaces whatever shell.css does with
    # those tokens. Flattening bg and the glows to black and transparent meant
    # the wallpaper vignette, the elevation shadows and the workspace-pill glow
    # all resolved to black-on-black or nothing at all — the styling was
    # applying and had nothing to show for it.

    # Takes the pointer image off the screen once it has been still that long
    # — the arrow parked in the middle of a film. Any use of the pointer brings
    # it back at once; typing does not, deliberately. Only the drawn image
    # goes: focus and position are unchanged, so no client is told the mouse
    # left. Milliseconds, not the seconds the idle block uses, because the
    # useful values here are not whole seconds. Zero or absent is off.
    cursor = {
      hide_after_ms = 2000;
    };

    idle = {
      lock_after = 600;
      lock_command = "${lib.getExe pkgs.swaylock} -f";
      blank_after = 900;
    };

    # binds_override appends/overrides keybindings on top of built-in defaults
    # without suppressing the default keymap.
    binds_override = {
      # Mute or unmute the microphone. wpctl talks to wireplumber, which is
      # what the bar's mic module and sway's push-to-talk binding already use,
      # so all three agree on one mute state.
      "Mod4+space" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      "Mod4+x" = "exec ${screenshotSelect}";
      "Mod4+Shift+x" = "exec ${screenshot}";
      "Print" = "exec ${screenshot}";
      "Mod4+Shift+p" = "shell power";
    }
    # Press to start dictating, press again to stop and transcribe the whole
    # take. Both keys sit under the left hand, and `Mod4+c` is otherwise unused
    # by the built-in keymap.
    // lib.optionalAttrs config.programs.voxtype.enable {
      "Mod4+c" = "exec ${lib.getExe config.programs.voxtype.package} record toggle";
    }
    # Same chord as in home/sway.nix. Throttles builds.slice down to a tenth of
    # the machine (and off the reserved cores) so a rebuild cannot stutter an
    # OBS capture; press again to give the CPU back. Only bound where the host
    # enables the module -- the Steam Deck imports this file too.
    // lib.optionalAttrs (osConfig.streamingMode.enable or false) {
      "Mod4+Shift+o" = "exec ${lib.getExe osConfig.streamingMode.package} toggle";
    };
  };
}
