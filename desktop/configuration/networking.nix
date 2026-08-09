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

    # Hard drop for the scanner netblock that spent 2026-08-08 probing sshd
    # (92.118.39.77 and sibling .50 are the same /24 rotation). fail2ban
    # handles fresh sources on its own; this pins the ones we already saw so
    # a rebuild does not reopen port 22 to them for the few minutes until
    # fail2ban re-bans them. Remove when the netblock stops showing up.
    nftables.tables.scanner-blocks = {
      family = "ip";
      content = ''
        chain input {
          type filter hook input priority -1; policy accept;
          iifname ${wanInterfaces} ip saddr 92.118.39.0/24 drop comment "internet SSH scanner netblock (2026-08-08)"
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
