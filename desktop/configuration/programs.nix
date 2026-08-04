{ pkgs, ... }:

{
  # Not in modules/default.nix on purpose -- the laptop must not get Steam.
  imports = [ ../../modules/programs/gaming.nix ];

  gaming.extest = false;

  # The only host here with a discrete GPU. The laptop stays on the CPU
  # backend, which is also the one the binary cache carries.
  voiceToText.gpu = true;

  programs.steam.extraPackages = with pkgs; [
    gamescope_git
    mangohud_git
  ];
}
