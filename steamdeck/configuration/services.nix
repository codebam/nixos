{ lib, ... }:

{
  services = {
    desktopManager.plasma6.enable = lib.mkForce false;
    openssh.settings.X11Forwarding = true;
    scx = {
      enable = true;
      scheduler = lib.mkForce "scx_lavd";
    };
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
  };
}
