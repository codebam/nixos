{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      claude-code
      dig
      distrobox
      git
      gparted
      libnotify
      mangohud
      nix-output-monitor
      nushell
      podman-compose
      rclone
      run0-sudo-shim
      via
      virt-manager
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
      (inputs.agenix.packages.${pkgs.system}.default.override {
        ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
      })
    ];
  };
}
