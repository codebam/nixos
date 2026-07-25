{ lib, ... }:

{
  services = {
    desktopManager.plasma6.enable = lib.mkForce false;
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
