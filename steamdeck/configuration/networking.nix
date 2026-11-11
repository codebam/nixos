_:

{
  # systemd-networkd-wait-online is already disabled for every host in
  # modules/system/networking.nix.
  networking = {
    hostName = "nixos-steamdeck";
  };

  # Same captive-portal rationale as laptop/configuration/networking.nix:
  # the Deck is portable, and strict DoT fails closed behind hijacked port
  # 53 with no way to reach the portal sign-in page. Opportunistic keeps
  # DoT to 1.1.1.1/9.9.9.9 when possible and falls back to plaintext
  # instead of failing.
  services.resolved.settings.Resolve.DNSOverTLS = "opportunistic";
}
