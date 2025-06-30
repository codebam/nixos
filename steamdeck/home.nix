{ pkgs, lib, ... }:
{

  home = {
    file.".local/share/kio/servicemenus/steam.desktop".text = ''
      [Desktop Entry]
      Type=Service
      MimeType=application/x-desktop;application/x-executable;text/plain;
      Actions=openInSteam
      X-KDE-Priority=TopLevel
      Icon=steam

      [Desktop Action openInSteam]
      Name=Open with Steam
      Icon=steam
      Exec=${pkgs.steam}/bin/steam %u
    '';
    packages = with pkgs; [
      rpcs3
      prismlauncher
      ryubing
      (writeShellScriptBin "steamos-add-to-steam" ''
        set -e
        add_to_steam() {
            encodedUrl="steam://addnonsteamgame/$(${pkgs.python3}/bin/python3 -c "import urllib.parse;print(urllib.parse.quote(\"$1\", safe=''\))")"
            touch /tmp/addnonsteamgamefile
            ${pkgs.steam}/bin/steam "$encodedUrl"
        }
        show_error() {
          if [ "$show_dialog" = "1" ]; then
              ${pkgs.kdePackages.kdialog}/bin/kdialog --title Error --error "$1"
          else
              echo "$1" >&2
          fi
        }
        if [ $(id -u) = "0" ]; then
            show_error "This script cannot be run as root"
            exit 1
        fi
        if [ "$XDG_SESSION_TYPE" = "tty" ] && ! pgrep -x steam >/dev/null 2>&1; then
           show_error "Cannot run this script from a tty if Steam is not running"
           exit 1
        fi
        if [ "$1" = "-ui" ]; then
            show_dialog=1
            shift
        fi
        file=$(realpath "$1")
        if [ ! -e "$file" ]
        then
            echo "Usage: steamos-add-to-steam [-ui] <path>"
            exit 1
        fi
        mime=$(kmimetypefinder "$file")
        case "$mime" in
            "application/x-desktop"|"application/x-ms-dos-executable"|"application/x-msdownload"|"application/vnd.microsoft.portable-executable")
                add_to_steam "$file"
                ;;
            "application/x-executable"|"application/vnd.appimage"|"application/x-shellscript")
                if [ -x "$file" ]; then
                    add_to_steam "$file"
                else
                    show_error "Unable to add non-Steam game. Is the file executable?"
                fi
                ;;
            *)
                show_error "Unsupported file type"
                ;;
        esac
      '')
    ];
  };

  wayland.windowManager.sway =
    let
      modifier = lib.mkForce "Mod1";
    in
    {
      config = rec {
        inherit modifier;
        output = {
          "X11-1" = {
            resolution = "1280x800";
          };
        };
      };
    };

  dconf.settings = {
    "org/gnome/desktop/a11y/applications" = {
      screen-keyboard-enabled = true;
    };
  };

  programs = {
    git = {
      signing = {
        key = "0F6D5021A87F92BA";
        signByDefault = true;
      };
    };
    i3status-rust = {
      bars = {
        default = {
          settings = {
            theme = {
              overrides = {
                separator = "";
              };
            };
          };
          icons = "awesome6";
          blocks = [
            { block = "focused_window"; }
            { block = "sound"; }
            {
              alert = 10.0;
              block = "disk_space";
              info_type = "available";
              interval = 60;
              path = "/";
              warning = 20.0;
            }
            {
              block = "memory";
              format = " $icon $mem_used_percents ";
            }
            { block = "cpu"; }
            { block = "load"; }
            {
              block = "time";
              interval = 60;
            }
            { block = "battery"; }
          ];
        };
      };
    };
  };
}
