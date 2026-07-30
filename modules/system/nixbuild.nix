# Builds happen on nixbuild.net rather than on this machine.
#
# Replaces the ephemeral GCP Spot builder, which worked but was capped at 32
# vCPUs by a global CPUS_ALL_REGIONS quota that Google declined to raise twice.
# nixbuild has no quota to ask permission for, bills per CPU-second actually
# used rather than per instance-hour, gives every derivation its own machine so
# an evaluation with many independent packages fans out completely, and cannot
# be preempted halfway through a two-hour WebKit build.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.nixbuild;

  # Keeps the muscle memory from the GCP module, which shipped a script of this
  # name. There is no VM to raise or tear down now, so this is a rebuild and
  # nothing else — `--builders ""` still forces the build to stay here.
  rebuildSwitch = pkgs.writeShellScriptBin "rebuild-switch" ''
    set -euo pipefail
    if command -v nh >/dev/null 2>&1; then
      # nh only passes nix flags on after `--`; without it a `--builders ""`
      # dies on an unknown option instead of building locally.
      exec nh os switch "${cfg.flakePath}" -- "$@"
    else
      exec ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch \
        --flake "${cfg.flakePath}" "$@"
    fi
  '';
in
{
  options.services.nixbuild = {
    # On by default, as the GCP module it replaces was: importing it is the
    # statement of intent, and nothing in the tree sets this explicitly.
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Build on nixbuild.net, and install the rebuild-switch script.";
    };

    identityFile = mkOption {
      type = types.str;
      default = "/home/codebam/.ssh/id_ed25519";
      description = ''
        Private key whose public half is registered with nixbuild.net. Read by
        the nix daemon, which runs as root, so it does not matter that this
        lives under a user's home — but the matching public key has to have
        been added to the nixbuild account or every build fails to connect.
      '';
    };

    maxJobs = mkOption {
      type = types.int;
      default = 100;
      description = ''
        How many derivations may be in flight there at once. High on purpose:
        each one gets its own machine, so this is a fan-out width rather than a
        core count, and the useful limit is how much the evaluation can
        parallelise.
      '';
    };

    flakePath = mkOption {
      type = types.str;
      default = "/persistent/etc/nixos";
      description = "Flake directory `rebuild-switch` builds from.";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh.extraConfig = ''
      Host eu.nixbuild.net
        PubkeyAcceptedKeyTypes ssh-ed25519
        ServerAliveInterval 60
        IdentityFile ${cfg.identityFile}
    '';

    programs.ssh.knownHosts.nixbuild = {
      hostNames = [ "eu.nixbuild.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
    };

    nix = {
      distributedBuilds = true;

      buildMachines = [
        {
          hostName = "eu.nixbuild.net";
          system = "x86_64-linux";
          maxJobs = cfg.maxJobs;
          # `big-parallel` is what marks a derivation as worth handing a whole
          # machine — WebKit and the kernel ask for it, and without it here
          # they would be built locally no matter what else is configured.
          supportedFeatures = [
            "benchmark"
            "big-parallel"
          ];
        }
      ];

      settings = {
        # Let the builder fetch dependencies from the public caches itself.
        # Without this every input is uploaded from here first, which on a
        # large closure costs more time than the build it is feeding.
        builders-use-substitutes = true;
      };
    };

    environment.systemPackages = [ rebuildSwitch ];
  };
}
