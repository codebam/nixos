_:

{
  networking = {
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
    ];
    firewall.allowedUDPPorts = [
      8211 # PalWorld port
      27015 # Steam query port
      1900 # UPnP
      8081 # Expo
      53 # Iodine
    ];
    firewall.allowedUDPPortRanges = [
      { from = 32768; to = 61000; } # UPnP
    ];
  };
}
