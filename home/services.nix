{ pkgs, ... }:

{
  services = {
    swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 120;
          command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
          resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * power on'";
        }
      ];
      events = {
        before-sleep = "${pkgs.sway}/bin/swaymsg 'output * power off'";
        after-resume = "${pkgs.sway}/bin/swaymsg 'output * power on'";
      };
    };
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      pinentry.package = pkgs.pinentry-gnome3;
    };
  };
}
