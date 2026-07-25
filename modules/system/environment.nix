{ pkgs, ... }:
{
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
