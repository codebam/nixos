{ pkgs, ... }:

{
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
      extest = {
        enable = false;
      };
      protontricks = {
        enable = true;
      };
      extraPackages = with pkgs; [
        gamescope_git
        mangohud_git
      ];
    };
    gamescope = {
      enable = true;
      package = pkgs.gamescope_git;
    };
    gamemode = {
      enable = true;
    };
  };
}
