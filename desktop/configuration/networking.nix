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
    ];
    firewall.allowedUDPPorts = [
      8211 # PalWorld port
      27015 # Steam query port
    ];
  };
}
