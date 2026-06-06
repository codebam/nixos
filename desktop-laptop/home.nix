{ pkgs, ... }:
{
  programs = {
    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-vaapi
        obs-pipewire-audio-capture
      ];
    };
  };
  services = {
    mako = {
      enable = false;
      settings = {
        layer = "overlay";
        default-timeout = 10000;
      };
    };
  };
}
