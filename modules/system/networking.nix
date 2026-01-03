{pkgs, ...}:
{
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    wireless.iwd = {
      enable = true;
      settings = {
        Scan = {
          DisableScanningWhileConnected = true;
        };
        General = {
          EnableNetworkConfiguration = true;
        };
      };
      # settings = {
      #   Rank = {
      #     BandModifier2_4GHz = 0.0;
      #     BandModifier5Ghz = 1.0;
      #   };
      # };
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
      trustedInterfaces = [ "virbr0" "tailscale0" ];
    };
  };
  systemd.services.wifi-performance = {
    description = "Disable Wi-Fi Power Save";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.iw}/bin/iw dev wlan0 set power_save off";
      RemainAfterExit = true;
    };
  };
}
