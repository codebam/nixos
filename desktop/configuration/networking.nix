_:

{
  networking = {
    nat = {
      enable = true;
      internalInterfaces = [ "dns0" ];
      externalInterface = "wlan0";
    };
    timeServers = [
      "time.cloudflare.com"
      "time.google.com"
      "0.ca.pool.ntp.org"
    ];
    hostName = "nixos-desktop";
    firewall = {
      allowedTCPPorts = [
        80 # nginx
        443 # nginx
        25575 # RCON port
        8212 # PalWorld
        8081 # Expo
        56789 # XRay
        3080 # LibreChat
      ];
      allowedUDPPorts = [
        8211 # PalWorld port
        27015 # Steam query port
        1900 # UPnP
        8081 # Expo
        56789 # XRay
      ];
      # No ephemeral-range accept here: 32768-61000/udp is the *source* port
      # range for outbound traffic, whose replies conntrack already accepts as
      # established/related. Opening it inbound only ever admitted unsolicited
      # traffic. UPnP itself needs 1900/udp, which is listed above.
    };
  };
}
