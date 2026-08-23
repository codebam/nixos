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
      # Every track boundary produced a burst of full-scale static: mopidy
      # swaps the next URI into playbin from about-to-finish without tearing
      # the sink down, and the library mixes 16- and 24-bit FLAC, so PCM of
      # one width reached a sink still configured for the other. The source
      # files decode clean and the stream URLs are fine -- it is the
      # renegotiation. Pinning the caps ahead of the sink means the sink is
      # only ever configured once and a track of any depth or rate is
      # converted to that before it gets there.
      #
      # F32LE/48000/2 is what the graph runs at natively -- media_ducker is
      # float32le 48000, and everything lands there -- so gstreamer does the
      # one conversion and pipewire does none. It also keeps the device off
      # the 44100 side of `default.clock.allowed-rates`, so a 44.1k track no
      # longer re-clocks the DAC.
      audio.output = "audioconvert ! audioresample ! audio/x-raw,format=F32LE,rate=48000,channels=2 ! pipewiresink";
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
