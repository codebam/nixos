{ pkgs, ... }:
{
  programs = {
    ccache = {
      enable = true;
    };
    uwsm = {
      enable = true;
      waylandCompositors = {
        sway = {
          prettyName = "Sway";
          comment = "Sway compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/sway";
        };
      };
    };
    fish = {
      enable = true;
    };
    nix-ld.enable = true;
    wireshark = {
      enable = true;
      usbmon.enable = true;
      package = pkgs.wireshark;
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-tty;
    };
    kdeconnect.enable = false;
    sway.enable = true;
    dconf.enable = true;
  };
}
