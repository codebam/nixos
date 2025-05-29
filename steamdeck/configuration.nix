{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

  networking = {
    hostName = "nixos-steamdeck";
  };

  jovian = {
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = "plasma";
    };
  };

  environment.etc."kio/servicemenus/steam.desktop".text = ''
    [Desktop Entry]
    Type=Service
    ServiceTypes=KonqPopupMenu/Plugin
    MimeType=application/x-desktop;application/x-executable;text/plain;
    Actions=openInSteam
    X-KDE-Priority=TopLevel
    Icon=steam

    [Desktop Action openInSteam]
    Name=Open with Steam
    Icon=steam
    Exec=${pkgs.steam}/bin/steam %u
  '';

  system = {
    stateVersion = "23.11";
  };
}
