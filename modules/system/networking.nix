_:
{
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    wireless.iwd = {
      enable = true;
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
      trustedInterfaces = [ "virbr0" ];
    };
  };
}
