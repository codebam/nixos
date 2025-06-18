{ config, pkgs, lib, inputs, ... }:

{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "nixos-desktop.local";
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
    settings = {
      max-jobs = 0;
    };
  };
}
