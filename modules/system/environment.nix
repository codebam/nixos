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
      vkbasalt
      sops
      ssh-to-age
      age
      age-plugin-yubikey
      # One command to move between the sched_ext schedulers this host has
      # installed, so a game session does not need a config rebuild. scxctl
      # talks to scx_loader over D-Bus; the polkit rule in
      # modules/security/default.nix already lets a member of wheel in a local
      # active session act without a prompt, so this needs no sudo.
      #
      #   scx-switch            running scheduler
      #   scx-switch game       scx_cake, the game-tuned one
      #   scx-switch work       scx_eevdf, the default
      #   scx-switch <name>     any installed scheduler, scx_ prefix optional
      (writeShellApplication {
        name = "scx-switch";
        runtimeInputs = [ scx-loader ];
        text = ''
          case "''${1:-}" in
            "" | status)
              exec scxctl get
              ;;
            game | cake)
              exec scxctl switch --sched scx_cake
              ;;
            work | default | eevdf)
              exec scxctl switch --sched scx_eevdf
              ;;
            *)
              sched="$1"
              case "$sched" in
                scx_*) ;;
                *) sched="scx_$sched" ;;
              esac
              exec scxctl switch --sched "$sched"
              ;;
          esac
        '';
      })
    ];
  };
}
