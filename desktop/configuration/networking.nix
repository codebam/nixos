{ config, lib, ... }:

let
  wanInterfaces = ''{ "wlan0", "enp6s0" }'';
in
{
  # Paired with the NAT and forwarding setup below, so kept here rather than in
  # modules/system/sysctl.nix. rp_filter is relaxed because inbound service
  # traffic is marked and policy-routed back out the interface it arrived on
  # (see the vpn-bypass table), which strict reverse-path filtering would drop.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
    # nginx binds 80/443 without CAP_NET_BIND_SERVICE.
    "net.ipv4.ip_unprivileged_port_start" = 80;
  };

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

    # Marks inbound connections to published ports so replies leave via the WAN
    # interface instead of the VPN default route. Desktop-only: it names this
    # host's interfaces, so it was dead weight on the laptop and Steam Deck.
    nftables.tables.vpn-bypass = {
      family = "ip";
      content =
        let
          inherit (config.networking) firewall;
          tcpPorts = builtins.concatStringsSep ", " (map toString firewall.allowedTCPPorts);
          udpPorts = builtins.concatStringsSep ", " (map toString firewall.allowedUDPPorts);
          tcpRanges = builtins.concatStringsSep ", " (
            map (r: "${toString r.from}-${toString r.to}") firewall.allowedTCPPortRanges
          );
          udpRanges = builtins.concatStringsSep ", " (
            map (r: "${toString r.from}-${toString r.to}") firewall.allowedUDPPortRanges
          );
          mark =
            proto: set: "iifname ${wanInterfaces} ${proto} dport { ${set} } ct state new ct mark set 0xca6c";
        in
        ''
          chain prerouting {
            type filter hook prerouting priority mangle; policy accept;
            ${lib.optionalString (tcpPorts != "") (mark "tcp" tcpPorts)}
            ${lib.optionalString (udpPorts != "") (mark "udp" udpPorts)}
            ${lib.optionalString (tcpRanges != "") (mark "tcp" tcpRanges)}
            ${lib.optionalString (udpRanges != "") (mark "udp" udpRanges)}
            ct mark 0xca6c meta mark set 0xca6c
          }
          chain output {
            type route hook output priority mangle; policy accept;
            ct mark 0xca6c meta mark set 0xca6c
          }
        '';
    };

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
        iifname ${wanInterfaces} ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } udp sport 1900 udp dport 32768-60999 accept comment "UPnP/SSDP discovery replies"
      '';
    };
  };
}
