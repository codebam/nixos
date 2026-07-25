{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.gaming.extest = lib.mkEnableOption ''
    Steam's extest layer, which translates X11 input events for games that
    bypass SDL. Wanted on the Steam Deck, not on the desktop
  '';

  config = {
    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        extraCompatPackages = with pkgs; [
          proton-ge-bin
          proton-cachyos_x86_64_v3
        ];
        protontricks.enable = true;
        extest.enable = config.gaming.extest;
      };
      gamescope = {
        enable = true;
        package = pkgs.gamescope_git;
      };
      gamemode.enable = true;
    };
  };
}
