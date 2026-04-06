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
    scx.enable = lib.mkForce false;
    lsfg-vk.enable = lib.mkForce false;
    tailscale.enable = lib.mkForce false;
    networkd-dispatcher.enable = lib.mkForce false;
    ratbagd.enable = lib.mkForce false;
    resolved.enable = true;
    speechd.enable = lib.mkForce false;
    udev = {
      packages = lib.mkForce [];
      extraRules = lib.mkForce "";
    };
    fwupd.enable = lib.mkForce false;
    pipewire.enable = lib.mkForce false;
    udisks2.enable = lib.mkForce false;
    gnome.gnome-keyring.enable = lib.mkForce false;
    pcscd.enable = lib.mkForce false;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
      openFirewall = true;
    };
  };
  system.stateVersion = "26.05";
}
