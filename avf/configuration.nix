{ pkgs, lib, ... }:

{
  boot.lanzaboote.enable = lib.mkForce false;
  networking.hostName = "nixos-avf";
  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "26.05";
}
