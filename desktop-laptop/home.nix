_: {
  # No obs-studio. It cost 1.9 GB of cef-binary for a browser source nothing
  # used, and turning that off is not free either: `browserSupport = false` is
  # not a variant the binary cache has, so every obs bump becomes a local
  # compile. Streaming is done with ffmpeg/kmsgrab instead -- see scripts/.
  #
  # If it comes back, note that `programs.obs-studio.package` is the wrong
  # place to override it: obs-studio-plugins build against `pkgs.obs-studio`
  # rather than against that option, so the un-overridden build stays in the
  # closure as their dependency and cef arrives with it. Override in the
  # overlay in modules/system/nixpkgs.nix, where both sides see it.
  services = {
    swaync = {
      enable = false;
    };
  };
}
