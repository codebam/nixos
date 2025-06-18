{ config, pkgs, lib, inputs, ... }:

{
  jovian = {
    decky-loader = {
      enable = true;
      user = "codebam";
      stateDir = "/home/codebam/.config/decky-loader";
    };
    steam = {
      enable = true;
      user = "codebam";
      autoStart = true;
      desktopSession = "gnome";
    };
    devices = {
      steamdeck = {
        enable = true;
      };
    };
    steamos = {
      useSteamOSConfig = true;
    };
  };
}
