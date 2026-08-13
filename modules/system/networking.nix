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
