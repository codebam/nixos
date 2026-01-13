{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      # claude-code
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
      # easyeffects
      # kdePackages.wallpaper-engine-plugin
      (inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
      })
    ];
  };
}
