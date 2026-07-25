{ pkgs, config, ... }:

let
  # Match the running compositor (sway_git), not pkgs.sway -- see home/sway.nix.
  swaymsg = "${config.wayland.windowManager.sway.package}/bin/swaymsg";
in
{
  services = {
    swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 120;
          command = "${swaymsg} 'output * power off'";
          resumeCommand = "${swaymsg} 'output * power on'";
        }
      ];
      events = {
        before-sleep = "${swaymsg} 'output * power off'";
        after-resume = "${swaymsg} 'output * power on'";
      };
    };
    wl-clip-persist = {
      enable = true;
      clipboardType = "both";
    };
    # Shadows the system-wide programs.gnupg.agent for this user: home-manager's
    # units in ~/.config/systemd/user take precedence over /etc/systemd/user, so
    # this is the agent codebam actually gets (graphical pinentry, not tty).
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      pinentry.package = pkgs.pinentry-gnome3;
    };
  };
}
