{
  pkgs,
  config,
  lib,
  osConfig,
  ...
}:

let
  # Match the running compositor (sway_git), not pkgs.sway -- see home/sway.nix.
  swaymsg = "${config.wayland.windowManager.sway.package}/bin/swaymsg";
  swaylock = lib.getExe pkgs.swaylock;

  # The deck runs the Viewport session, not sway: swayidle's swaymsg half
  # cannot work there, and its lock would fire 110 seconds behind a handheld
  # nobody wants to re-unlock. Viewport manages the deck's idle itself
  # (idle in home/viewport.nix).
  isDeck = osConfig.networking.hostName == "nixos-steamdeck";
in
{
  services = {
    swayidle = {
      enable = !isDeck;
      # swayidle is sway's idle manager: every command it runs is a swaymsg
      # or a swaylock, and Viewport manages its own idle and lock (idle in
      # home/viewport.nix). Bind it to sway-session.target, which only sway
      # raises, rather than the default graphical-session.target, which every
      # Wayland session raises: the desktop logs into Viewport too, and under
      # it swayidle fired swaylock at 110s and before sleep — a second locker
      # over the compositor's own. Viewport locks before sleep itself now
      # (power::watch_sleep), so nothing is lost by leaving it out.
      systemdTargets = [ "sway-session.target" ];
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
      # Cache the PIN/passphrase for 8 hours, so the YubiKey prompts at most
      # once a day. Without these the agent runs on its built-in defaults —
      # default-cache-ttl 600 (the every-10-minutes re-prompt) and
      # max-cache-ttl 7200. max is the absolute cap from the first prompt,
      # default the idle expiry each use refreshes; both at 8 hours means
      # one prompt per working day even under continuous use. A running agent
      # keeps its startup TTLs until reloaded, so after a switch run
      # `systemctl --user reload gpg-agent` -- switching alone changes nothing.
      defaultCacheTtl = 28800;
      maxCacheTtl = 28800;
      # SSH auth through the agent has its own pair of TTLs, untouched by the
      # two above: without these, YubiKey SSH (git push, logins) falls back to
      # the built-in 1800 idle / 7200 max and re-prompts every half hour.
      defaultCacheTtlSsh = 28800;
      maxCacheTtlSsh = 28800;
      # pinentry-tty in a terminal window of its own under a graphical
      # session, on the calling tty when there is none. See pkgs/pinentry-auto.nix.
      pinentry.package = pkgs.pinentry-auto.override { terminal = config.defaultTerminal; };
    };
  };

  # All user units live here (was: systemd.nix) so there is one place to
  # look for autostarted user services.
  systemd.user.services = {
    # The target binding above keeps swayidle out of a Viewport login, but a
    # restart starts a unit whatever wants it — and home-manager restarts a
    # changed unit on switch. SWAYSOCK is the one variable only a sway
    # session imports into the user manager (sway's own exec line hands it
    # over), so the condition refuses the restart under Viewport too.
    swayidle.Unit.ConditionEnvironment = lib.mkForce "SWAYSOCK";
    # A launcher, not a supervisor: the tmux server is meant to outlive the
    # unit (persistence is the point of tmux), and in practice it already
    # does — the server runs while the unit sits dead. The old unit was
    # Type=forking with `new-session -d -s default`, which fails with
    # "duplicate session" whenever the server is already up; systemd then
    # waited the full 90s DefaultTimeoutStartSec for a daemon PID that never
    # came, and home-manager's switch waits on that job — every switch that
    # touched the unit hung for a minute and a half. Oneshot with an
    # idempotent start completes at once whether or not the session exists.
    # No ExecStop: sd-switch restarts a changed unit on every switch, and
    # `kill-session` there would destroy the live session to install a new
    # unit file. Stopping the unit now just marks it inactive; the server
    # stays, and the next start adopts it.
    tmux = {
      Unit = {
        Description = "Tmux server";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [
          "TERM=xterm-256color"
          "COLORTERM=truecolor"
        ];
        ExecStart = "${pkgs.writeShellScript "tmux-server-start" ''
          sock=$1
          if ${lib.getExe pkgs.tmux} -S "$sock" has-session -t default 2>/dev/null; then
            exit 0
          fi
          exec ${lib.getExe pkgs.tmux} -S "$sock" new-session -d -s default
        ''} /run/user/%U/tmux-%U/default";
        Restart = "on-failure";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };
}
