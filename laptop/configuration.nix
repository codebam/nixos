{ inputs, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nixpkgs.overlays = [
    (final: prev: {
      # linuxPackages_testing = inputs.rc2.legacyPackages.${pkgs.system}.linuxPackages_testing;
      # linuxPackages_latest = inputs.linux-latest-update.legacyPackages.${pkgs.system}.linuxPackages_testing;
      # bcachefs-tools = inputs.bcachefs-fix.packages.${pkgs.system}.bcachefs;
    })
  ];

  system = {
    autoUpgrade = {
      enable = true;
      flake = "github:codebam/nixos#laptop";
      dates = "09:00";
    };
    stateVersion = "23.11";
  };
}
