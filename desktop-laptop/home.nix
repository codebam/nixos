{ pkgs, ... }:
{
  programs = {
    obs-studio = {
      enable = true;
      plugins = [ pkgs.obs-studio-plugins.obs-vaapi ];
    };
  };
  services = {
    mako = {
      enable = true;
      settings = {
        layer = "overlay";
        default-timeout = 10000;
      };
    };
  };
}
