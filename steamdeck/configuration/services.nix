{ lib, ... }:

{
  services = {
    desktopManager.plasma6.enable = lib.mkForce true;
    scx = {
      enable = true;
      scheduler = lib.mkForce "scx_lavd";
    };
  };
}
