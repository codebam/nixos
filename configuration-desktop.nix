{ inputs, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration-desktop.nix
    ];

  services = {
    hardware.openrgb = {
      enable = true;
    };

    foldingathome = {
      enable = true;
      user = "codebam";
    };

    ollama = {
      enable = true;
      acceleration = "rocm";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      };
    };
  };

  programs = {
    corectrl = {
      enable = true;
      gpuOverclock.enable = true;
      gpuOverclock.ppfeaturemask = "0xffffffff";
    };
  };

  hardware = {
    opengl = {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr.icd
      ];
    };
  };

  nixpkgs.overlays = [
    (final: prev: {
      linuxPackages_testing = inputs.rc2.legacyPackages.${pkgs.system}.linuxPackages_testing;
      # linuxPackages_latest = inputs.linux-latest-update.legacyPackages.${pkgs.system}.linuxPackages_testing;
      # bcachefs-tools = inputs.bcachefs-fix.packages.${pkgs.system}.bcachefs;
    })
  ];

  system = {
    autoUpgrade = {
      enable = true;
      flake = "github:codebam/nixos#desktop";
      dates = "09:00";
    };
    stateVersion = "23.11";
  };
}
