{ pkgs, lib, ... }:

{
  boot.lanzaboote.enable = lib.mkForce false;
  networking.hostName = "nixos-avf";
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = "aarch64-linux";
  avf.defaultUser = "codebam";
  system.stateVersion = "26.05";
}
