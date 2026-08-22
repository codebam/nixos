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

  # Opportunistic rather than the strict "true" from
  # modules/services/default.nix. ivpn hands systemd-resolved a plain-IP
  # resolver on the wgivpn link (resolvectl dns wgivpn 10.0.254.2, with ~. and
  # default-route true), and that resolver speaks no DoT and has no name to
  # validate a certificate against -- under strict DoT every query through the
  # tunnel fails, and ivpn's killswitch drops port 53 to anything else, so the
  # host has no working DNS at all while connected. Opportunistic still uses
  # DoT to 1.1.1.1/9.9.9.9 whenever the network allows it.
  services.resolved.settings.Resolve.DNSOverTLS = "opportunistic";

  networking = {
    # NAT used to exist for a dns0 interface that is gone. Do not re-enable
    # until something actually needs to be forwarded off this host.
    # NTP servers live in ./services.nix (services.timesyncd.servers); setting
    # networking.timeServers here too was two sources for one truth.
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
      # Only what is actually served. Six holes were removed here because
      # nothing had been listening behind them: 25575 (RCON), 8212+8211
      # (PalWorld), 56789 (XRay), 3080 (LibreChat), 8081 (Expo, and its dev
      # server binds ::1 anyway), and 27015 (Steam query, which
      # programs.steam.dedicatedServer.openFirewall opens on its own when a
      # server is actually running).
      #
      # An unused open port is not harmless here: ip_unprivileged_port_start
      # is 80 so that nginx can bind without the capability, which means any
      # unprivileged process on this host can claim one of these and be
      # reachable from the internet. Re-add a line when the service behind it
      # comes back, not before.
      allowedTCPPorts = [
        80 # nginx
        443 # nginx
      ];
      allowedUDPPorts = [
        1900 # UPnP
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
