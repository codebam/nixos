{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.gcp-builder;

  startupScript = pkgs.writeText "builder-startup.sh" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix &>/dev/null; then
      mkdir -p /etc/nix
      cat <<'EOF' > /etc/nix/nix.conf
experimental-features = nix-command flakes
trusted-users = root codebam debian
max-jobs = auto
cores = 0
EOF

      curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
    fi
  '';

  gcpCacheFillScript = pkgs.writeText "gcp-cache-fill-startup.sh" ''
    #!/usr/bin/env bash
    set -uo pipefail

    if ! command -v nix &>/dev/null; then
      mkdir -p /etc/nix
      echo "experimental-features = nix-command flakes" > /etc/nix/nix.conf
      curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
    fi

    export PATH="/nix/var/nix/profiles/default/bin:$PATH"

    REPO_URL="https://github.com/codebam/nixos.git"
    WORK_DIR="/tmp/nixos-build"

    mkdir -p "$WORK_DIR"
    git clone "$REPO_URL" "$WORK_DIR" || exit 1
    cd "$WORK_DIR"

    echo "==> Building NixOS configuration on GCP..."
    nix build .#nixosConfigurations.nixos-desktop.config.system.build.toplevel --extra-experimental-features "nix-command flakes" || true

    echo "==> Self-destructing GCP VM..."
    gcloud compute instances delete nix-builder-async --zone="${cfg.zone}" --project="${cfg.project}" --quiet
  '';

  gcpCacheFill = pkgs.writeShellScriptBin "gcp-cache-fill" ''
    set -euo pipefail

    PROJECT="${cfg.project}"
    ZONE="${cfg.zone}"
    INSTANCE="nix-builder-async"
    MACHINE_TYPE="${cfg.machineType}"
    DISK_SIZE="${cfg.diskSize}"

    echo "==> [gcp-builder] Launching fire-and-forget GCP cache fill VM ($INSTANCE)..."
    ${pkgs.google-cloud-sdk}/bin/gcloud compute instances create "$INSTANCE" \
      --project="$PROJECT" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --provisioning-model=SPOT \
      --instance-termination-action=DELETE \
      --auto-delete-boot-disk \
      --scopes=cloud-platform \
      --boot-disk-size="$DISK_SIZE" \
      --boot-disk-type=pd-balanced \
      --image-family=debian-12 \
      --image-project=debian-cloud \
      --metadata-from-file=startup-script=${gcpCacheFillScript} \
      --quiet >/dev/null 2>&1 &

    echo "==> [gcp-builder] Oneshot cache fill launched on GCP background. Terminal freed immediately!"
  '';

  rebuildSwitch = pkgs.writeShellScriptBin "rebuild-switch" ''
    set -euo pipefail

    PROJECT="${cfg.project}"
    ZONE="${cfg.zone}"
    INSTANCE="${cfg.instanceName}"
    MACHINE_TYPE="${cfg.machineType}"
    DISK_SIZE="${cfg.diskSize}"
    BUCKET="${cfg.cacheBucket}"

    ASYNC_MODE=false
    USE_GCP=true
    PREV_ARG=""
    for arg in "$@"; do
      if [ "$arg" = "--async" ] || [ "$arg" = "--bg" ]; then
        ASYNC_MODE=true
      elif [ "$PREV_ARG" = "--builders" ] && [ -z "$arg" ]; then
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

    if [ "$ASYNC_MODE" = "true" ]; then
      exec ${gcpCacheFill}/bin/gcp-cache-fill
    fi

    if [ "$USE_GCP" = "false" ]; then
      echo "==> [gcp-builder] Local build requested (--builders). Skipping GCP VM provisioning."
      if command -v nh >/dev/null 2>&1; then
        exec nh os switch "${cfg.flakePath}" "$@"
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
      --auto-delete-boot-disk \
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
      nh os switch "${cfg.flakePath}" "$@" -- --build-host "$BUILD_HOST"
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
    machineType = mkOption {
      type = types.str;
      default = "c2d-standard-32";
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
      description = "GCS Binary Cache Bucket name.";
    };
    flakePath = mkOption {
      type = types.str;
      default = "/persistent/etc/nixos";
      description = "Flake directory path for rebuild-switch.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ rebuildSwitch gcpCacheFill ];
  };
}
