{ lib, ... }:

{
  services = {
    # jovian turns plasma6 on; sway is the session here.
    desktopManager.plasma6.enable = lib.mkForce false;
    # scx/scx_lavd config comes from modules/services/default.nix, which is
    # off; only the desktop opts in through the main-snapshot overlay in
    # modules/system/nixpkgs.nix. The plain false there also keeps Jovian's
    # mkDefault true from turning scx on here.
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
  };
}
