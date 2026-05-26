{ pkgs, ... }:

{
  services = {
    swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = 600;
          command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
          resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * power on'";
        }
      ];
      events = {
        before-sleep = "${pkgs.sway}/bin/swaymsg 'output * power off'";
        after-resume = "${pkgs.sway}/bin/swaymsg 'output * power on'";
      };
    };
  };
}
