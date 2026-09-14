{
  lib,
  ...
}:
{
  # Nothing here waits for the network at boot; the unit's ExecStart override
  # that used to sit in modules/system/systemd.nix was dead because of this.
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
    # The vpn-bypass table is desktop-only (it names that host's interfaces) and
    # lives in desktop/configuration/networking.nix.
    nftables.enable = true;

    # OpenSandbox publishes its bridge-mode sandbox ports on 0.0.0.0 (upstream
    # opensandbox_server/services/docker/port_allocator.py hardcodes that bind
    # scope), while only the loopback lifecycle server is meant to reach them. Drop the range on every other interface before the firewall's
    # trusted-interface accepts, which would otherwise let tailscale0 through.
    # Keep the range in sync with home/opensandbox.nix.
    nftables.tables.opensandbox-guard = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -10; policy accept;
          iifname != "lo" tcp dport 40000-40200 drop comment "OpenSandbox sandbox ports are loopback-only"
        }
      '';
    };

    firewall = {
      enable = true;
      # Kept deliberately narrow. 80/443 are opened on the desktop only, in
      # desktop/configuration/networking.nix -- nothing on the laptop or Steam
      # Deck serves HTTP. Steam's own ports come from programs.steam.*.openFirewall.
      allowedTCPPorts = [ ];
      allowedUDPPorts = [
        5353 # mDNS (systemd-resolved)
      ];
      trustedInterfaces = [
        "tailscale0"
      ];
    };
  };
}
