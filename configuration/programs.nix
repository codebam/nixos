{ pkgs, ... }:
{
  programs = {
    fish = {
      enable = true;
    };
    nix-ld.enable = true;
    wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    kdeconnect.enable = true;
    sway.enable = true;
    dconf.enable = true;
  };
}
