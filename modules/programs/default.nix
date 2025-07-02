{ pkgs, ... }:
{
  programs = {
    ccache = {
      enable = true;
    };
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
      pinentryPackage = pkgs.pinentry-tty;
    };
    kdeconnect.enable = true;
    sway.enable = true;
    dconf.enable = true;
  };
}
