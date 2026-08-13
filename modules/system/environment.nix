{ pkgs, ... }:
{
  # No i18n.supportedLocales trim here, deliberately -- it makes this closure
  # *bigger*, and the obvious fix for that is worse.
  #
  # The option builds a second, small locale-archive for LOCALE_ARCHIVE (5.4
  # MB) but does not replace the full 222 MB `pkgs.glibcLocales`, which stays
  # because steam's FHS environment symlinks usr/lib64/locale/locale-archive
  # straight out of it and buildFHSEnv exposes no way to point that elsewhere.
  # So the trim alone costs 5.4 MB and saves nothing.
  #
  # Overriding pkgs.glibcLocales in an overlay does remove the 222 MB -- and
  # rebuilds 6240 derivations to do it, because perl, python, tcl and most of
  # the stdenv test machinery take glibcLocales as a build input. That is a
  # near-full source rebuild now and on every nixpkgs bump after, for 217 MB.
  #
  # Re-evaluate if steam ever leaves this host; the 222 MB goes with it.

  environment = {
    etc."nixos".source = "/persistent/etc/nixos";

    systemPackages = with pkgs; [
      bubblewrap
      ladspaPlugins
      lsp-plugins
      dig
      git
      gparted
      libnotify
      nh
      nix-output-monitor
      nushell
      rclone
      wl-clipboard
      xdg-utils
      # System monitoring and debugging tools
      htop
      btop
      iotop
      strace
      lsof
      # Archive and compression tools
      unzip
      zip
      _7zz
      # Wayland forwarding over SSH
      # waypipe
      # Wallpaper Engine
      # linux-wallpaperengine
      # easyeffects
      # kdePackages.wallpaper-engine-plugin
      vkbasalt
      sops
      ssh-to-age
      age
      age-plugin-yubikey
    ];
  };
}
