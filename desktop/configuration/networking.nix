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
      # SSDP discovery replies. upnpc M-SEARCHes 239.255.255.250:1900 from an
      # ephemeral port; the IGD answers unicast from its own address, so the
      # reply does not match the conntrack entry (different source address) and
      # arrives as a new packet. This replaces a blanket 32768-61000/udp accept:
      # same discovery, but only from a LAN address with source port 1900.
      extraInputRules = ''
        iifname { "wlan0", "enp6s0" } ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } udp sport 1900 udp dport 32768-60999 accept comment "UPnP/SSDP discovery replies"
      '';
    };
  };
}
