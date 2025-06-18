{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./home.nix
    ./sway.nix
    ./programs.nix
    ./services.nix
    ./xdg.nix
    ./stylix.nix
  ];
}
