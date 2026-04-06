{ pkgs, lib, ... }:

{
  boot.lanzaboote.enable = lib.mkForce false;
  networking.hostName = "nixos-avf";
  networking.useDHCP = lib.mkForce true;
  hardware.graphics.enable32Bit = lib.mkForce false;
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
    ];
  };
  services = lib.mkForce {
    scx.enable = false;
    lsfg-vk.enable = false;
    tailscale.enable = false;
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
      settings = {
        PasswordAuthentication = false;
      };
      openFirewall = true;
    };
  };
  zramSwap.enable = lib.mkForce false;
  system.stateVersion = "26.05";
}
