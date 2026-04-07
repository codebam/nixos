{ pkgs, lib, ... }:

{
  imports = [
    ../modules/users/default.nix
  ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  boot = lib.mkForce {
    loader = {
      systemd-boot.enable = false;
    };
  };
  nixpkgs.hostPlatform = "aarch64-linux";
  avf.defaultUser = "codebam";
  environment = lib.mkForce {
    systemPackages = with pkgs; [
      dig
      git
      nushell
      rclone
      unzip
      zip
      _7zz
      helix
    ];
  };
  networking = {
    hostName = "nixos-avf";
    useDHCP = true;
    networkmanager = {
      enable = false;
    };
    wireless.iwd = {
      enable = false;
    };
    nftables = {
      enable = true;
    };
    firewall = rec {
      enable = true;
      allowedTCPPorts = [
      ];
      allowedUDPPorts = allowedTCPPorts;
      allowedTCPPortRanges = [];
      allowedUDPPortRanges = allowedTCPPortRanges;
      trustedInterfaces = [ "enp0s12" "tailscale0" ];
    };
  };
  services = lib.mkForce {
    ananicy.enable = false;
    scx.enable = false;
    tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };
    networkd-dispatcher.enable = false;
    ratbagd.enable = false;
    resolved.enable = true;
    speechd.enable = false;
    udev = {
      packages = [];
      extraRules = "";
    };
    fwupd.enable = false;
    pipewire.enable = false;
    udisks2.enable = false;
    gnome.gnome-keyring.enable = false;
    pcscd.enable = false;
    openssh = {
      enable = true;
      ports = [ 8022 ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
      openFirewall = true;
    };
  };
  zramSwap.enable = lib.mkForce false;
  systemd.services.wifi-performance.enable = lib.mkForce false;
  xdg = lib.mkForce {
    portal.enable = false;
    portal.wlr.enable = false;
  };
  programs = lib.mkForce {
    uwsm.enable = false;
    ccache.enable = false;
    wireshark.enable = false;
    sway.enable = false;
    dconf.enable = false;
    gnupg.agent.enable = false;
    fish.enable = true;
  };
  fonts.packages = lib.mkForce [];
  hardware = lib.mkForce {
    bluetooth.enable = false;
    uinput.enable = false;
    graphics.enable = false;
    graphics.enable32Bit = false;
    keyboard.qmk.enable = false;
  };
  system.stateVersion = "26.05";
}
