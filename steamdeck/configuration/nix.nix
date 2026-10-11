_:

{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        # FQDN, not `nixos-desktop.local`: mDNS only answers on the LAN, so a
        # Deck sitting on the tailnet cannot resolve it and every build it
        # should offload is compiled locally instead. MagicDNS answers the
        # FQDN from anywhere on the tailnet.
        hostName = "nixos-desktop.tail7d7a2.ts.net";
        system = "x86_64-linux,i686-linux";
        maxJobs = 15;
        speedFactor = 10;
        supportedFeatures = [ "big-parallel" ];
        sshUser = "codebam";
        sshKey = "/home/codebam/.ssh/id_ed25519";
      }
      {
        hostName = "codebam.duckdns.org";
        system = "x86_64-linux,i686-linux";
        maxJobs = 15;
        speedFactor = 1;
        supportedFeatures = [ "big-parallel" ];
        sshUser = "codebam";
        sshKey = "/home/codebam/.ssh/id_ed25519";
      }
    ];
  };
}
