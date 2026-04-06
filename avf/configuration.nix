{ pkgs, lib, ... }:

{
  boot.lanzaboote.enable = lib.mkForce false;
  networking.hostName = "nixos-avf";
  networking.useDHCP = lib.mkForce true;
  networking.networkmanager.enable = lib.mkForce false;
  nixpkgs.hostPlatform = "aarch64-linux";
  avf.defaultUser = "codebam";
  system.stateVersion = "26.05";
}
