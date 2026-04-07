{ pkgs, lib, ... }:

{
  home = {
    packages = with pkgs; lib.mkForce [
      helix
    ];
    extraOutputsToInstall = [];
    stateVersion = "26.05";
  };
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;
  wayland.windowManager.sway.enable = lib.mkForce false;
  xdg = {
    enable = lib.mkForce false;
  };
  programs = {
    man.enable = false;
    git = lib.mkForce {
      # signing = {
      #   key = "0271B12CCF0A185B01EB25FA4B1C30CAAB93976B";
      #   signByDefault = true;
      # };
    };
  };
}
