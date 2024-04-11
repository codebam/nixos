{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;

  time.timeZone = "America/Toronto";

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  environment.etc."pipewire/pipewire.conf.d/93-high-sample-rate.conf".text = ''
  context.properties = {
    default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 384000 768000 ]
    default.clock.rate = 384000
  }
  '';

  users.users.codebam = {
    isNormalUser = true;
    home = "/home/codebam";
    description = "Sean Behan";
    extraGroups = ["wheel" "networkmanager"];
    packages = with pkgs; [
      flatpak
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    rcm
    grim
    slurp
    wl-clipboard
    mako
    waybar
    wofi
    nodejs
    nodePackages.wrangler
    tmux
    weechat
    xdg-utils
    (pass.withExtensions (subpkgs: with subpkgs; [
      pass-audit
      pass-otp
      pass-genphrase
    ]))
  ];
  fonts.packages = with pkgs; [
    fira-code
    fira-code-symbols
    font-awesome
  ];

  xdg = {
    autostart.enable = true;
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal
        pkgs.xdg-desktop-portal-gtk
      ];
      wlr.enable = true;
    };
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  services.flatpak.enable = true;
  services.udisks2.enable = true;
  services.gnome.gnome-keyring.enable = true;

  services.pcscd.enable = true;
  programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  nixpkgs.config.allowUnfree = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };

  programs.corectrl = {
    enable = true;
    gpuOverclock.enable = true;
    gpuOverclock.ppfeaturemask = "0xffffffff";
  };

  system.stateVersion = "23.11";
}
