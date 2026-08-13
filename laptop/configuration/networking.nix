_:

{
  networking = {
    hostName = "nixos-laptop";
  };

  # Opportunistic rather than the strict "true" the other hosts get from
  # modules/services/default.nix. This is the machine that leaves the house,
  # and a captive portal hijacks port 53 by design: with strict DoT resolved
  # refuses the hijacked answer, so name resolution fails outright and the
  # portal's own sign-in page cannot be reached to fix it. Opportunistic still
  # uses DoT to 1.1.1.1/9.9.9.9 whenever the network lets it, and falls back
  # to plaintext instead of failing closed when it does not.
  services.resolved.settings.Resolve.DNSOverTLS = "opportunistic";
}
