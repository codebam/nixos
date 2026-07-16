{ lib, ... }:

{
  networking = {
    hostName = "nixos-steamdeck";
  };

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
