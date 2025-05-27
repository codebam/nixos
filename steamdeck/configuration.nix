{pkgs, ...}:
{
  imports = [
    ./hardware-configuration.nix
  ];

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

  system = {
    stateVersion = "23.11";
  };
}
