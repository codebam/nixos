{ config, pkgs, lib, inputs, ... }:
{
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    wireless.iwd = {
      enable = true;
    };
    nftables = {
      enable = true;
    };
    firewall = rec {
      enable = true;
      allowedTCPPorts = [
        80
        443
        3389
        5353
        27037
      ];
      allowedUDPPorts = allowedTCPPorts;
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = allowedTCPPortRanges;
      checkReversePath = false;
      trustedInterfaces = [ "virbr0" ];
    };
  };
}
