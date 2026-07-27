{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gcpNixBuilder;
  stateDir = cfg.credentialsDir;

  gcloudEnv = ''
    # Per-uid so root (nix-daemon) and the interactive user don't fight over one
    # gcloud config dir. On tmpfs, so a reboot re-activates from the key.
    export CLOUDSDK_CONFIG="/run/gcp-nix-builder/gcloud-$(id -u)"
    export CLOUDSDK_CORE_PROJECT=${cfg.project}
    export CLOUDSDK_CORE_DISABLE_PROMPTS=1
    export CLOUDSDK_COMPONENT_MANAGER_DISABLE_UPDATE_CHECK=1
    # One activation per boot; re-activating on every SSH connection would add
    # a second of latency to each ProxyCommand.
    if [ ! -e "$CLOUDSDK_CONFIG/.activated" ]; then
      mkdir -p "$CLOUDSDK_CONFIG"
      gcloud auth activate-service-account --key-file=${stateDir}/sa.json >/dev/null 2>&1
      touch "$CLOUDSDK_CONFIG/.activated"
    fi
    instance_status() {
      gcloud compute instances describe ${cfg.instance} --zone=${cfg.zone} \
        --format='value(status)' 2>/dev/null
    }
    instance_ip() {
      gcloud compute instances describe ${cfg.instance} --zone=${cfg.zone} \
        --format='value(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null
    }
  '';

  # ssh(1) ProxyCommand. Resolving the address here rather than pinning one in
  # ssh_config is what lets the instance keep an ephemeral IP: a reserved
  # address bills whether or not the builder is running.
  connect = pkgs.writeShellApplication {
    name = "gcp-nix-builder-connect";
    runtimeInputs = [
      pkgs.google-cloud-sdk
      pkgs.socat
    ];
    text = ''
      ${gcloudEnv}

      status="$(instance_status)"
      if [ "$status" != "RUNNING" ]; then
        # Cost guard. Exiting non-zero makes nix log "cannot connect" and fall
        # back to building locally rather than silently starting a paid VM.
        if [ -e /run/gcp-nix-builder.disabled ]; then
          echo "gcp-nix-builder: disabled, not starting instance" >&2
          exit 1
        fi
        echo "gcp-nix-builder: starting $status instance..." >&2
        gcloud compute instances start ${cfg.instance} --zone=${cfg.zone} >/dev/null 2>&1
      fi

      ip="$(instance_ip)"
      [ -n "$ip" ] || { echo "gcp-nix-builder: no external address" >&2; exit 1; }

      for _ in $(seq 1 90); do
        if timeout 3 bash -c "</dev/tcp/$ip/22" 2>/dev/null; then
          exec socat - "TCP:$ip:22"
        fi
        sleep 2
      done
      echo "gcp-nix-builder: $ip:22 never became reachable" >&2
      exit 1
    '';
  };

  ctl = pkgs.writeShellApplication {
    name = "gcp-nix-builder";
    runtimeInputs = [
      pkgs.google-cloud-sdk
      pkgs.openssh
      pkgs.nixos-rebuild
    ];
    text = ''
      ${gcloudEnv}

      cmd="''${1:-status}"
      [ $# -gt 0 ] && shift

      case "$cmd" in
        up)
          [ "$(instance_status)" = "RUNNING" ] || \
            gcloud compute instances start ${cfg.instance} --zone=${cfg.zone}
          echo "running at $(instance_ip)"
          ;;
        down)
          # Flush anything worth keeping before the store goes cold.
          ssh ${cfg.hostAlias} 'sudo systemctl start --wait nix-cache-push.service' || true
          gcloud compute instances stop ${cfg.instance} --zone=${cfg.zone}
          ;;
        status)
          echo "instance: $(instance_status)"
          echo "address:  $(instance_ip)"
          echo "guard:    $([ -e /run/gcp-nix-builder.disabled ] && echo disabled || echo enabled)"
          ;;
        on)  rm -f /run/gcp-nix-builder.disabled; echo "auto-start enabled" ;;
        off) touch /run/gcp-nix-builder.disabled; echo "auto-start disabled" ;;
        ssh) exec ssh ${cfg.hostAlias} "$@" ;;
        push)
          ssh ${cfg.hostAlias} 'sudo systemctl start --wait nix-cache-push.service'
          ssh ${cfg.hostAlias} 'sudo journalctl -u nix-cache-push.service -n 20 --no-pager'
          ;;
        cache)
          # Storage and class-A operations are what the bucket actually bills
          # for, so stopping uploads is the switch that matters. Reading stays
          # available; dropping the substituter as well means setting
          # services.gcpNixBuilder.cache.useAsSubstituter = false and rebuilding.
          case "''${1:-status}" in
            off)
              ssh ${cfg.hostAlias} 'sudo touch /etc/nix/cache-push-disabled &&
                sudo systemctl disable --now nix-cache-push.timer'
              echo "cache uploads off"
              ;;
            on)
              ssh ${cfg.hostAlias} 'sudo rm -f /etc/nix/cache-push-disabled &&
                sudo systemctl enable --now nix-cache-push.timer'
              echo "cache uploads on"
              ;;
            size)
              gcloud storage du -s "gs://${cfg.cache.bucket}"
              ;;
            purge)
              read -rp "delete every object in gs://${cfg.cache.bucket}? [y/N] " a
              [ "$a" = y ] || exit 1
              gcloud storage rm -r "gs://${cfg.cache.bucket}/**" || true
              ;;
            status|*)
              if ssh ${cfg.hostAlias} 'test -e /etc/nix/cache-push-disabled' 2>/dev/null; then
                echo "uploads: off"
              else
                echo "uploads: on"
              fi
              echo "substituter: ${
                if cfg.cache.useAsSubstituter then "enabled" else "disabled"
              } (build-time)"
              gcloud storage du -s "gs://${cfg.cache.bucket}" 2>/dev/null || true
              ;;
          esac
          ;;
        gc)
          ssh ${cfg.hostAlias} 'sudo systemctl start --wait nix-gc.service'
          ssh ${cfg.hostAlias} "df -h / | tail -1"
          ;;
        log)
          ssh ${cfg.hostAlias} 'sudo journalctl -u google-startup-scripts -n 60 --no-pager'
          ;;
        rebuild)
          # --max-jobs 0 refuses to build anything locally, so the whole closure
          # is forced onto the builder instead of nix scheduling by speedFactor.
          # (builders-use-substitutes is already set in modules/system/nix.nix,
          # which is what stops the builder pulling deps through this machine.)
          exec nixos-rebuild "''${1:-switch}" \
            --flake ${cfg.flake} \
            --max-jobs 0 --elevate=run0 \
            "''${@:2}"
          ;;
        *)
          echo "usage: gcp-nix-builder {up|down|status|on|off|ssh|push|gc|log" >&2
          echo "                        |cache {on|off|status|size|purge}" >&2
          echo "                        |rebuild [switch|boot|test]}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.services.gcpNixBuilder = {
    enable = lib.mkEnableOption "the on-demand GCP Nix remote builder";

    project = lib.mkOption {
      type = lib.types.str;
      default = "codebam-nixbuild";
      description = "GCP project holding the builder instance and cache bucket.";
    };

    zone = lib.mkOption {
      type = lib.types.str;
      default = "us-east1-b";
      description = "Zone the builder instance lives in.";
    };

    instance = lib.mkOption {
      type = lib.types.str;
      default = "nix-builder";
      description = "Name of the builder instance.";
    };

    credentialsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gcp-nix-builder";
      description = ''
        Holds sa.json, id_ed25519, aws-credentials and known_hosts. Group-readable
        by wheel so `gcp-nix-builder ssh` works without escalating.
      '';
    };

    hostAlias = lib.mkOption {
      type = lib.types.str;
      default = "gcp-nix-builder";
      description = "ssh_config Host alias used by nix.buildMachines.";
    };

    maxJobs = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "Parallel derivations to schedule on the builder; match its vCPU count.";
    };

    speedFactor = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Relative build speed. Above the local machine's implicit 1 so nix prefers it.";
    };

    flake = lib.mkOption {
      type = lib.types.str;
      default = "/persistent/etc/nixos";
      description = "Flake `gcp-nix-builder rebuild` operates on.";
    };

    cache = {
      bucket = lib.mkOption {
        type = lib.types.str;
        default = "codebam-nix-cache";
        description = "GCS bucket used as a binary cache.";
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east1";
        description = "Bucket region, needed for S3 request signing.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "codebam-nix-cache-1:hLFAU7tQwQEAyyOoVPO8PU1TIoftIuZwFgEzJCsJSWc=";
        description = "Signing key the builder generated; clients need it to trust the cache.";
      };
      useAsSubstituter = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Fetch from the GCS cache. Requires HMAC credentials at ${stateDir}/aws-credentials.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      ctl
      connect
    ];

    nix = {
      distributedBuilds = true;
      buildMachines = [
        {
          hostName = cfg.hostAlias;
          system = "x86_64-linux";
          inherit (cfg) maxJobs speedFactor;
          sshUser = "builder";
          sshKey = "${stateDir}/id_ed25519";
          supportedFeatures = [
            "big-parallel"
            "benchmark"
            "nixos-test"
          ];
        }
      ];

      settings = lib.mkIf cfg.cache.useAsSubstituter {
        extra-substituters = [
          "s3://${cfg.cache.bucket}?endpoint=storage.googleapis.com&region=${cfg.cache.region}"
        ];
        extra-trusted-public-keys = [ cfg.cache.publicKey ];
      };
    };

    # ControlMaster keeps the ProxyCommand (two gcloud round-trips) off the hot
    # path for every connection after the first.
    programs.ssh.extraConfig = ''
      Host ${cfg.hostAlias}
        User builder
        # The daemon (root) reads the first; ssh skips it unreadable for other
        # users and falls through to the per-user copy. Both must be 0600 --
        # ssh refuses a group-readable private key outright.
        IdentityFile ${stateDir}/id_ed25519
        IdentityFile ~/.ssh/id_gcp_nix_builder
        IdentitiesOnly yes
        ProxyCommand ${lib.getExe connect}
        UserKnownHostsFile ${stateDir}/known_hosts
        StrictHostKeyChecking accept-new
        ControlMaster auto
        ControlPath /run/gcp-nix-builder-ssh-%r
        ControlPersist 300
        ServerAliveInterval 30
        ConnectTimeout 300
    '';

    # The S3 substituter is fetched by the daemon, not the calling user, so the
    # HMAC credentials have to be in the daemon's environment.
    systemd.services.nix-daemon.environment.AWS_SHARED_CREDENTIALS_FILE =
      lib.mkIf cfg.cache.useAsSubstituter "${stateDir}/aws-credentials";

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 root wheel -"
      # Sticky and world-writable: each uid makes its own gcloud config below.
      "d /run/gcp-nix-builder 1777 root root -"
    ];

    # gcloud's activation marker and the ssh ControlPath both live on tmpfs, so
    # the first connection after a boot re-authenticates.
    preservation.preserveAt."/persistent".directories = [
      {
        directory = stateDir;
        user = "root";
        group = "wheel";
        mode = "0750";
      }
    ];
  };
}
