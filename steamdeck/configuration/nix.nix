_:

{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        # FQDN, not `nixos-desktop.local`: mDNS only answers on the LAN, so a
        # Deck sitting on the tailnet cannot resolve it and every build it
        # should offload is compiled locally instead. MagicDNS answers the
        # FQDN from anywhere on the tailnet. The former WAN duckdns.org
        # fallback was removed: it leaked builds/SSH over the WAN and
        # doubled offered jobs (2x15 on an 8-core builder).
        hostName = "nixos-desktop.tail7d7a2.ts.net";
        system = "x86_64-linux,i686-linux";
        maxJobs = 8;
        speedFactor = 10;
        supportedFeatures = [ "big-parallel" ];
        sshUser = "codebam";
        sshKey = "/home/codebam/.ssh/id_ed25519";
      }
    ];
  };
}
