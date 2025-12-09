{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      claude-code
      dig
      git
      gparted
      libnotify
      nh
      nix-output-monitor
      nushell
      rclone
      via
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
      waypipe
      # Wallpaper Engine
      linux-wallpaperengine
      kdePackages.wallpaper-engine-plugin
      (inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
      })
      (wrapRetroArch {
        cores = with libretro; [
          genesis-plus-gx # Sega
          snes9x # SNES
          beetle-psx-hw # PlayStation
          dolphin # GameCube / Wii
          stella # Atari 2600
          # mame # MAME
          # mame2000 # MAME
          # mame2003 # MAME
          # mame2015 # MAME
          # mame2016 # MAME
          # neocd # Neo ?
          fbneo # various
          mupen64plus # Nintendo 64
          nestopia # Nintendo NES
          mgba # Game Boy Advance
          # fuse # ZX Spectrum
          melonds # Nintendo DS
          desmume # Nintendo DS
          desmume2015 # Nintendo DS
          ppsspp # PlayStation Portable
          citra # Nintendo 3DS
        ];
      })
    ];
  };
}
