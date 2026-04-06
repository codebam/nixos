{ pkgs, lib, ... }:

{
  boot.lanzaboote.enable = lib.mkForce false;
  networking.hostName = "nixos-avf";
  networking.useDHCP = lib.mkForce true;
  hardware.graphics.enable32Bit = lib.mkForce false;
  services.scx.enable = lib.mkForce false;
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
  system.stateVersion = "26.05";
}
