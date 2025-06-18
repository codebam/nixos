{ config, pkgs, lib, inputs, ... }:

{
  boot = {
    plymouth = {
      enable = true;
    };
    initrd.systemd = {
      enable = true;
    };
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        configurationLimit = 50;
      };
      timeout = 0;
      efi.canTouchEfiVariables = true;
    };

    kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 0;
    };

    extraModulePackages = [ ];
  };
}
