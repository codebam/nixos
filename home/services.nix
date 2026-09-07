{
  pkgs,
  config,
  lib,
  ...
}:

let
  # Match the running compositor (sway_git), not pkgs.sway -- see home/sway.nix.
  swaymsg = "${config.wayland.windowManager.sway.package}/bin/swaymsg";
  swaylock = lib.getExe pkgs.swaylock;
in
{
  services = {
    swayidle = {
      enable = true;
      timeouts = [
        {
          # Lock before the outputs go off so a resume never lands
          # on an unlocked session.
          timeout = 110;
          command = "${swaylock} -f";
        }
        {
          timeout = 120;
          command = "${swaymsg} 'output * power off'";
          resumeCommand = "${swaymsg} 'output * power on'";
        }
      ];
      events = {
        before-sleep = "${swaylock} -f; ${swaymsg} 'output * power off'";
        after-resume = "${swaymsg} 'output * power on'";
      };
    };
    wl-clip-persist = {
      enable = true;
      clipboardType = "both";
    };
    # Shadows the system-wide programs.gnupg.agent for this user: home-manager's
    # units in ~/.config/systemd/user take precedence over /etc/systemd/user, so
    # this is the agent codebam actually gets.
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      # pinentry-tty in a terminal window of its own under a graphical
      # session, on the calling tty when there is none. See pkgs/pinentry-auto.nix.
      pinentry.package = pkgs.pinentry-auto.override { terminal = config.defaultTerminal; };
    };
  };

  # All user units live here (was: systemd.nix for tmux, sops.nix for
  # iamb-login) so there is one place to look for autostarted user services.
  systemd.user.services = {
    tmux = {
      Unit = {
        Description = "Tmux server";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "forking";
        Environment = [
          "TERM=xterm-256color"
          "COLORTERM=truecolor"
        ];
        ExecStart = "${lib.getExe pkgs.tmux} -S /run/user/%U/tmux-%U/default new-session -d -s default";
        ExecStop = "${lib.getExe pkgs.tmux} -S /run/user/%U/tmux-%U/default kill-session -t default";
        Restart = "always";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    iamb-login = {
      Unit = {
        Description = "Auto-login for iamb Matrix client";
        ConditionPathExists = [
          "/run/secrets/unredacted.org"
          "!%h/.local/share/iamb/profiles/unredacted.org/session.json"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${
          pkgs.writeShellApplication {
            name = "iamb-login-service";
            runtimeInputs = [
              pkgs.curl
              pkgs.gnugrep
              pkgs.coreutils
            ];
            text = ''
              set -euo pipefail
              SECRET_PATH="/run/secrets/unredacted.org"
              if [ -f "$SECRET_PATH" ]; then
                PASSWORD=$(head -n 1 "$SECRET_PATH")
                RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
                  -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"codebam\"},\"password\":\"$PASSWORD\"}" \
                  https://matrix.unredacted.org/_matrix/client/v3/login)
                if echo "$RESPONSE" | grep -q "access_token"; then
                  mkdir -p "$HOME/.local/share/iamb/profiles/unredacted.org"
                  echo "$RESPONSE" > "$HOME/.local/share/iamb/profiles/unredacted.org/session.json"
                fi
              fi
            '';
          }
        }/bin/iamb-login-service";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
