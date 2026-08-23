{ pkgs, ... }:

{
  # Navidrome behind an MPD socket, so ncmpcpp (home/programs.nix) can play
  # it: mpd itself speaks no Subsonic and has no backend plugin interface, so
  # mopidy stands in as the daemon, with mopidy-subidy talking to Navidrome
  # and mopidy-mpd serving the protocol on 6600.
  #
  # A home-manager user service rather than the system one this used to be
  # (5954d2c, dropped in 47979cf): the system unit had to be forced to run as
  # codebam and handed /run/user/1000 through BindReadOnlyPaths to reach
  # pipewire. A user service is in that session already.
  services.mopidy = {
    enable = true;
    extensionPackages = with pkgs; [
      mopidy-subidy
      mopidy-mpd
      # Playback controls land on the same MPRIS bus as everything else, so
      # playerctl and the waybar module keep working.
      mopidy-mpris
    ];
    settings = {
      core.restore_state = true;
      # pipewiresink is in mopidy's own gstreamer plugin path already; no
      # GST_PLUGIN_SYSTEM_PATH_1_0 of our own is needed.
      audio.output = "pipewiresink";
      mpd = {
        enabled = true;
        # Loopback only. The old system unit bound 0.0.0.0, and there is
        # nothing on the network that should be driving this.
        hostname = "127.0.0.1";
        port = 6600;
      };
      # Nothing here uses the web frontend or a local library. No
      # `local.enabled`: mopidy-local is not among the extensions above, and
      # mopidy warns on a config section with no extension behind it.
      http.enabled = false;
      file.enabled = false;
    };
    # Read after ~/.config/mopidy/mopidy.conf, so this supplies the whole
    # [subidy] section -- url and username included, not just the password.
    # Rendered in desktop/configuration/sops.nix.
    extraConfigFiles = [ "/run/secrets/rendered/mopidy-subidy.conf" ];
  };
}
