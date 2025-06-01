{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking = {
    hostName = "nixos-laptop";
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_xanmod_latest;
    supportedFilesystems = [ "bcachefs" ];
  };

  nixpkgs.overlays = [ (final: prev: { }) ];

  system = {
    autoUpgrade = {
      enable = true;
      flake = "github:codebam/nixos#nixos-laptop";
      dates = "09:00";
    };
    stateVersion = "23.11";
  };
}
