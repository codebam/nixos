{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../hardware-configuration.nix
    ./networking.nix
    ./environment.nix
    ./age.nix
    ./users.nix
    ./boot.nix
    ./systemd.nix
    ./services.nix
    ./programs.nix
    ./hardware.nix
    ./preservation.nix
    ./nix.nix
    ./nixpkgs.nix
    ./system.nix
  ];
}
