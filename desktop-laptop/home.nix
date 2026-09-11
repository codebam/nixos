{ pkgs, ... }:
{
  programs = {
    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        # NVIDIA Broadcast is RTX-only; this plugin gives the AMD desktop and
        # the laptop the same AI segmentation without a green screen.
        obs-backgroundremoval
        obs-vaapi
        obs-pipewire-audio-capture
      ];
    };
  };
}
