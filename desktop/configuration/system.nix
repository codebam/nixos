{ config, pkgs, lib, inputs, ... }:

{
  system = {
    autoUpgrade = {
      enable = true;
      flake = "/etc/nixos";
      operation = "switch";
      dates = "daily";
      randomizedDelaySec = "10min";
      allowReboot = false;
    };
    stateVersion = "25.11";
  };
}
