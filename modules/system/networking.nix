{
  pkgs,
  config,
  lib,
  ...
}:
{
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  networking = {
    useNetworkd = true;
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
          EnableNetworkConfiguration = false;
        };
      };
    };
    nftables = {
      enable = true;
      tables = {
        vpn-bypass = {
          family = "ip";
          content =
            let
              tcpPorts = builtins.concatStringsSep ", " (map toString config.networking.firewall.allowedTCPPorts);
              udpPorts = builtins.concatStringsSep ", " (map toString config.networking.firewall.allowedUDPPorts);
              tcpRanges = builtins.concatStringsSep ", " (
                map (r: "${toString r.from}-${toString r.to}") config.networking.firewall.allowedTCPPortRanges
              );
              udpRanges = builtins.concatStringsSep ", " (
                map (r: "${toString r.from}-${toString r.to}") config.networking.firewall.allowedUDPPortRanges
              );
            in
            ''
              chain prerouting {
                type filter hook prerouting priority mangle; policy accept;
                ${lib.optionalString (
                  tcpPorts != ""
                ) ''iifname { "wlan0", "enp6s0" } tcp dport { ${tcpPorts} } ct state new ct mark set 0xca6c''}
                ${lib.optionalString (
                  udpPorts != ""
                ) ''iifname { "wlan0", "enp6s0" } udp dport { ${udpPorts} } ct state new ct mark set 0xca6c''}
                ${lib.optionalString (
                  tcpRanges != ""
                ) ''iifname { "wlan0", "enp6s0" } tcp dport { ${tcpRanges} } ct state new ct mark set 0xca6c''}
                ${lib.optionalString (
                  udpRanges != ""
                ) ''iifname { "wlan0", "enp6s0" } udp dport { ${udpRanges} } ct state new ct mark set 0xca6c''}
                ct mark 0xca6c meta mark set 0xca6c
              }
              chain output {
                type route hook output priority mangle; policy accept;
                ct mark 0xca6c meta mark set 0xca6c
              }
            '';
        };
      };
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
      trustedInterfaces = [
        "virbr0"
        "tailscale0"
      ];
    };
  };
}
