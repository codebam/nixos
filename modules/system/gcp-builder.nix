{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.gcp-builder;

  # These run on a Debian GCE VM, not on NixOS, so they must NOT be built with
  # writeShellScript: that stamps a /nix/store bash path as line 1, which does
  # not exist on the VM, and the metadata script runner dies with exit 127
  # before a single line of the script executes. writeTextFile keeps our own
  # `#!/usr/bin/env bash` as line 1.
  #
  # Every line below is also indented uniformly on purpose. Nix strips the
  # common leading whitespace from an '' block, so a single flush-left line
  # (an unindented heredoc body, say) would defeat the stripping and leave the
  # shebang indented -- which the kernel does not recognise as a shebang.
  vmScript =
    name: text:
    pkgs.writeTextFile {
      inherit name text;
      executable = true;
      checkPhase = "${pkgs.stdenv.shellDryRun} $target";
    };

  startupScript = vmScript "builder-startup.sh" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix &>/dev/null; then
      mkdir -p /etc/nix
      printf '%s\n' \
        "experimental-features = nix-command flakes" \
        "trusted-users = root codebam debian" \
        "max-jobs = auto" \
        "cores = 0" > /etc/nix/nix.conf

      curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
    fi
  '';

  # Making and unmaking the cache bucket, which is all that is left of the
  # binary cache this module used to fill.
  #
  # Kept as a command rather than as part of a build because the two are not
  # the same decision: building on a Spot VM is a thing to do often, and
  # standing a public cache back up is a thing to do once and then live with.
  gcpCacheBucket = pkgs.writeShellScriptBin "gcp-cache-bucket" ''
    set -euo pipefail

    PROJECT="${cfg.project}"
    ZONE="${cfg.zone}"
    BUCKET="${cfg.cacheBucket}"

    usage() {
      echo "usage: gcp-cache-bucket {create|delete|status}" >&2
      echo "  create   make gs://$BUCKET, world-readable" >&2
      echo "  delete   remove it and everything in it" >&2
      echo "  status   say whether it exists and how big it is" >&2
      exit 2
    }

    case "''${1:-}" in
      create)
        if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
          echo "==> gs://$BUCKET already exists"
          exit 0
        fi
        echo "==> creating gs://$BUCKET in ''${ZONE%-*}"
        gcloud storage buckets create "gs://$BUCKET" \
          --project="$PROJECT" \
          --location="''${ZONE%-*}" \
          --uniform-bucket-level-access
        # Public read is not an oversight. Nix fetches a substituter over plain
        # HTTPS with no credentials, so a private bucket answers every request
        # with 403 and the cache is silently useless. What goes in it is signed
        # build output of public packages, and the signature is what makes it
        # trustworthy rather than the obscurity of the URL.
        gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
          --project="$PROJECT" \
          --member=allUsers \
          --role=roles/storage.objectViewer >/dev/null
        echo "==> created. Nothing fills it: this module no longer has that"
        echo "    part, and nothing reads it until a substituter names it"
        echo "    *and* its public key."
        ;;
      delete)
        if ! gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
          echo "==> gs://$BUCKET does not exist"
          exit 0
        fi
        gcloud storage du -s "gs://$BUCKET" || true
        echo "==> deleting gs://$BUCKET and everything in it"
        gcloud storage rm -r "gs://$BUCKET"
        ;;
      status)
        if gcloud storage buckets describe "gs://$BUCKET" \
             --project="$PROJECT" --format="value(name,location)" 2>/dev/null; then
          gcloud storage du -s "gs://$BUCKET" || true
        else
          echo "gs://$BUCKET does not exist"
        fi
        ;;
      *) usage ;;
    esac
  '';

  rebuildSwitch = pkgs.writeShellScriptBin "rebuild-switch" ''
    set -euo pipefail

    PROJECT="${cfg.project}"
    ZONE="${cfg.zone}"
    INSTANCE="${cfg.instanceName}"
    MACHINE_TYPE="${cfg.machineType}"
    DISK_SIZE="${cfg.diskSize}"

    USE_GCP=true
    PREV_ARG=""
    for arg in "$@"; do
      if [ "$PREV_ARG" = "--builders" ] && [ -z "$arg" ]; then
        USE_GCP=false
      elif [[ "$arg" =~ ^--builders= ]]; then
        val="''${arg#--builders=}"
        val="''${val#\"}"
        val="''${val%\"}"
        if [ -z "$val" ] || [[ "$val" =~ ^\'*\'*$ ]]; then
          USE_GCP=false
        fi
      fi
      PREV_ARG="$arg"
    done


    if [ "$USE_GCP" = "false" ]; then
      echo "==> [gcp-builder] Local build requested (--builders). Skipping GCP VM provisioning."
      if command -v nh >/dev/null 2>&1; then
        # nh takes nix flags only after `--`; without it, `rebuild-switch
        # --builders ""` dies on an unknown option instead of building locally.
        exec nh os switch "${cfg.flakePath}" -- "$@"
      else
        exec nixos-rebuild switch --flake "${cfg.flakePath}" "$@"
      fi
    fi

    cleanup() {
      local exit_code=$?
      echo "==> [gcp-builder] Tearing down GCP builder instance ($INSTANCE)..."
      ${pkgs.google-cloud-sdk}/bin/gcloud compute instances delete "$INSTANCE" \
        --zone="$ZONE" \
        --project="$PROJECT" \
        --quiet 2>/dev/null || true
      echo "==> [gcp-builder] Teardown complete."
      exit $exit_code
    }

    trap cleanup EXIT INT TERM HUP

    echo "==> [gcp-builder] Spinning up ephemeral GCP Spot builder ($INSTANCE in $PROJECT)..."
    ${pkgs.google-cloud-sdk}/bin/gcloud compute instances create "$INSTANCE" \
      --project="$PROJECT" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --provisioning-model=SPOT \
      --instance-termination-action=DELETE \
      --scopes=cloud-platform \
      --boot-disk-size="$DISK_SIZE" \
      --boot-disk-type=pd-balanced \
      --image-family=debian-12 \
      --image-project=debian-cloud \
      --metadata-from-file=startup-script=${startupScript} \
      --quiet

    echo "==> [gcp-builder] Waiting for VM SSH & Nix installation..."
    until ${pkgs.google-cloud-sdk}/bin/gcloud compute ssh "$INSTANCE" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --command="command -v nix &>/dev/null || /nix/var/nix/profiles/default/bin/nix --version &>/dev/null" 2>/dev/null; do
      sleep 3
    done

    echo "==> [gcp-builder] Configuring SSH host alias..."
    ${pkgs.google-cloud-sdk}/bin/gcloud compute config-ssh --quiet 2>/dev/null || true

    BUILD_HOST="$INSTANCE.$ZONE.$PROJECT"

    echo "==> [gcp-builder] Running NixOS rebuild-switch with build host ($BUILD_HOST)..."
    if command -v nh >/dev/null 2>&1; then
      nh os switch "${cfg.flakePath}" -- "$@" --build-host "$BUILD_HOST"
    else
      nixos-rebuild switch --flake "${cfg.flakePath}" --build-host "$BUILD_HOST" "$@"
    fi

    echo "==> [gcp-builder] Rebuild completed successfully."
  '';
in
{
  options.services.gcp-builder = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GCP ephemeral NixOS builder integration and rebuild-switch script.";
    };
    project = mkOption {
      type = types.str;
      default = "codebam-nixbuild";
      description = "GCP Project ID for the builder.";
    };
    zone = mkOption {
      type = types.str;
      default = "us-east1-b";
      description = "GCP Zone for the builder.";
    };
    instanceName = mkOption {
      type = types.str;
      default = "nix-builder";
      description = "Instance name for the ephemeral builder.";
    };
    repoUrl = mkOption {
      type = types.str;
      default = "https://github.com/codebam/nixos.git";
      description = "Flake repository the cache fill VM clones and builds.";
    };
    machineType = mkOption {
      type = types.str;
      default = "n2-standard-32";
      description = "GCP Machine Type for the builder.";
    };
    diskSize = mkOption {
      type = types.str;
      default = "100GB";
      description = "Boot disk size for the builder.";
    };
    cacheBucket = mkOption {
      type = types.str;
      default = "codebam-nix-cache";
      description = ''
        The GCS bucket `gcp-cache-bucket` makes and removes.

        Nothing fills it and nothing reads it: the binary cache this module used
        to keep was deleted once the compositor stopped building an engine from
        source. The name is here so that standing one back up is a command
        rather than an archaeology exercise.
      '';
    };

    flakePath = mkOption {
      type = types.str;
      default = "/persistent/etc/nixos";
      description = "Flake directory path for rebuild-switch.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ rebuildSwitch gcpCacheBucket ];
  };
}
