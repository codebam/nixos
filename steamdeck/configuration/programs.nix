{ pkgs, ... }:

{
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
      extest = {
        enable = true;
      };
      protontricks = {
        enable = true;
      };
    };
    gamescope = {
      enable = true;
    };
    gamemode = {
      enable = true;
    };
  };
}
