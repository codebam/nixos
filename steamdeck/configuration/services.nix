{ lib, ... }:

{
  services = {
    # jovian turns plasma6 on; sway is the session here.
    desktopManager.plasma6.enable = lib.mkForce false;
    # scx/scx_lavd comes from modules/services/default.nix.
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
  };
}
