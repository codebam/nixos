{ config, pkgs, lib, inputs, ... }:

{
  systemd = {
    services = {
      systemd-remount-fs = {
        enable = false;
      };
    };
  };
}
