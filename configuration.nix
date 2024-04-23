{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 1w";
  };
  nix.settings.auto-optimise-store = true;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.wireless.iwd.enable = true;
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 25565 ];
    checkReversePath = false;
  };

  time.timeZone = "America/Toronto";

  services.fwupd.enable = true;

  security.polkit.enable = true;
  systemd = {
    user.extraConfig = ''
        DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '';
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
    };
  };

  security.pam.services.swaylock = {};

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    configPackages = [
      (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-high-sample-rate.conf" ''
        context.properties = {
          default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 384000 768000 ]
          default.clock.rate = 384000
        }
          '')
    ];
  };

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
    nixd
    rcm
    grim
    slurp
    wl-clipboard
    nodejs
    weechat
    xdg-utils
    (pass.withExtensions (subpkgs: with subpkgs; [
      pass-audit
      pass-otp
      pass-genphrase
    ]))
    playerctl
    libnotify
    aerc
  ];

  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    fira-code
    fira-code-symbols
    fira-code-nerdfont
    font-awesome
  ];

  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "gtk";
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };
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

  programs.corectrl = {
    enable = true;
    gpuOverclock.enable = true;
    gpuOverclock.ppfeaturemask = "0xffffffff";
  };

  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  services.hardware.openrgb = {
    enable = true;
  };

  hardware.opengl.enable = true;

  programs.dconf.enable = true;

  system.stateVersion = "23.11";
}
