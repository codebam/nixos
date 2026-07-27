{ pkgs, lib, ... }:

let
  screenshot = pkgs.writeShellScript "screenshot" ''
    set -euo pipefail
    shots="$HOME/Pictures/Screenshots"
    mkdir -p "$shots"
    out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
    ${pkgs.grim}/bin/grim "$out"
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$out"
  '';

  screenshotSelect = pkgs.writeShellScript "screenshot-select" ''
    set -euo pipefail
    shots="$HOME/Pictures/Screenshots"
    mkdir -p "$shots"
    temp_file=$(mktemp -t screenshot-XXXXXX.png)
    imv_pid=""
    cleanup() {
      [ -n "$imv_pid" ] && kill "$imv_pid" 2>/dev/null || true
      rm -f "$temp_file"
    }
    trap cleanup EXIT
    ${pkgs.grim}/bin/grim "$temp_file"
    ${pkgs.imv}/bin/imv -f "$temp_file" &
    imv_pid=$!
    sleep 0.2
    region=$(${pkgs.slurp}/bin/slurp || true)
    if [ -n "$region" ]; then
        out="$shots/screenshot-$(date +%Y%m%d%H%M%S).png"
        ${pkgs.imagemagick}/bin/magick "$temp_file" -crop "$region" +repage "$out"
        ${pkgs.wl-clipboard}/bin/wl-copy --type image/png < "$out"
    fi
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

    outputs = {
      "*" = {
        max_refresh = true;
      };
    };

    adaptive_sync = true;
    bar = "auto";
    logo = false;
    tutorial = false;

    theme = {
      bg = "#000000";
      glow-1 = "transparent";
      glow-2 = "transparent";
      bar-bg = "#000000";
      bar-border = "#1a1a1a";
    };

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
    };
  };
}
