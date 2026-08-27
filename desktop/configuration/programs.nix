{ pkgs, ... }:

{
  # Not in modules/default.nix on purpose -- the laptop must not get Steam.
  imports = [ ../../modules/programs/gaming.nix ];

  gaming.extest = false;

  programs.steam.extraPackages = with pkgs; [
    gamescope_git
    mangohud_git
  ];
}
