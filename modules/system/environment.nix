{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      claude-code
      dig
      git
      gparted
      libnotify
      mangohud
      nh
      nix-output-monitor
      nushell
      rclone
      run0-sudo-shim
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
      (inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
      })
    ];
  };
}
