_:

{
  networking = {
    nat = {
      enable = true;
      internalInterfaces = [ "dns0" "lo" ];
      externalInterface = "wlan0";
    };
    timeServers = [
      "time.cloudflare.com"
      "time.google.com"
      "0.ca.pool.ntp.org"
    ];
    hostName = "nixos-desktop";
    firewall.allowedTCPPorts = [
      25575 # RCON port
      8212 # PalWorld
      8081 # Expo
      56789 # XRay
      3080 # LibreChat
    ];
    firewall.allowedUDPPorts = [
      8211 # PalWorld port
      27015 # Steam query port
      1900 # UPnP
      8081 # Expo
      53 # Iodine
      56789 # XRay
    ];
    firewall.allowedUDPPortRanges = [
      { from = 32768; to = 61000; } # UPnP
    ];
  };
}
