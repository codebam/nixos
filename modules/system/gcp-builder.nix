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

  # Runs as root on the Spot VM via GCE metadata startup-script. Everything it
  # prints lands on serial port 1, which is what `gcp-cache-fill -f` tails.
  gcpCacheFillScript = vmScript "gcp-cache-fill-startup.sh" ''
    #!/usr/bin/env bash
    # No `set -e`: a failed stage must still fall through to the EXIT trap so the
    # Spot VM always tears itself down instead of idling on the meter.
    set -uo pipefail

    # GCE runs startup scripts with no HOME, and the Nix installer aborts with
    # "$HOME is not set". Nix also writes per-user state under it later.
    export HOME=/root
    export USER=root

    INSTANCE="${cfg.asyncInstanceName}"
    ZONE="${cfg.zone}"
    PROJECT="${cfg.project}"
    BUCKET="${cfg.cacheBucket}"
    KEY_FILE="/root/cache-priv-key.pem"
    CACHE_DIR="/var/tmp/nix-cache"
    WORK_DIR="/var/tmp/nixos-build"
    LOG_FILE="/var/log/gcp-cache-fill.log"

    # GCE sends startup-script output to journald, not to the serial port, so
    # `gcp-cache-fill -f` would otherwise only ever show the boot log and a
    # login prompt. Log to a file and have a detached tail relay it to ttyS0
    # (serial port 1).
    #
    # Deliberately NOT `exec > >(tee /dev/ttyS0)`: with process substitution, a
    # tee that cannot open /dev/ttyS0 dies and the first echo takes SIGPIPE,
    # killing the script before it prints anything. A plain file redirect has
    # no such coupling, and it keeps stdout a non-tty so nix emits plain log
    # lines instead of an ANSI progress bar.
    # The relay is supervised: an unsupervised `tail -F` that dies (write error
    # on ttyS0, getty contention, SIGHUP) silently ends serial output while the
    # build keeps running, which is indistinguishable from a hang. Restart it if
    # it exits. `-n 0` on each restart avoids replaying the whole log.
    : > "$LOG_FILE"
    setsid bash -c "while :; do tail -n 0 -F '$LOG_FILE' > /dev/ttyS0 2>/dev/null; sleep 2; done" \
      </dev/null >/dev/null 2>&1 &
    exec >> "$LOG_FILE" 2>&1

    self_destruct() {
      local rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "==> [gcp-builder-async] FAILED (exit $rc)."
        echo "==> [gcp-builder-async] Holding VM ${toString cfg.failureHoldMinutes}m so the logs survive."
        echo "==> [gcp-builder-async] Inspect: gcloud compute ssh $INSTANCE --zone=$ZONE --project=$PROJECT --command='sudo cat $LOG_FILE'"
        sleep $(( ${toString cfg.failureHoldMinutes} * 60 ))
      fi
      echo "==> [gcp-builder-async] Self-destructing GCP VM ($INSTANCE)..."
      sync
      sleep 5
      gcloud compute instances delete "$INSTANCE" --zone="$ZONE" --project="$PROJECT" --quiet
    }
    trap self_destruct EXIT

    echo "==> [gcp-builder-async] Installing base dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    # Debian GCE images fire apt-daily/unattended-upgrades on boot, which holds
    # the apt lock for minutes. Without an explicit lock timeout these calls
    # block silently; with it they queue and report. Stopping the timers first
    # keeps the wait short.
    systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null
    systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
    apt-get -o DPkg::Lock::Timeout=600 update -qq
    apt-get -o DPkg::Lock::Timeout=600 install -y -qq git curl xz-utils
    echo "==> [gcp-builder-async] Base dependencies ready."

    echo "==> [gcp-builder-async] Starting Nix daemon setup..."
    if ! command -v nix &>/dev/null; then
      curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes || exit 1
    fi

    export PATH="/nix/var/nix/profiles/default/bin:$PATH"

    # This MUST come after the installer: it writes its own /etc/nix/nix.conf and
    # silently discards anything already there. Configuring before it is why the
    # builder ignored its own cache and rebuilt wpewebkit from source.
    #
    # build-users-group is the installer's own setting; drop it and every build
    # fails. extra-* keeps the cache.nixos.org defaults. The bucket is public,
    # so reading from it needs no credentials.
    echo "==> [gcp-builder-async] Configuring nix.conf (cache substituter)..."
    mkdir -p /etc/nix
    printf '%s\n' \
      "build-users-group = nixbld" \
      "experimental-features = nix-command flakes" \
      "max-jobs = auto" \
      "cores = 0" \
      "extra-substituters = https://storage.googleapis.com/${cfg.cacheBucket} ${concatStringsSep " " cfg.extraSubstituters}" \
      "extra-trusted-public-keys = ${cfg.cachePublicKey} ${concatStringsSep " " cfg.extraTrustedPublicKeys}" \
      "fallback = true" > /etc/nix/nix.conf
    systemctl restart nix-daemon 2>/dev/null || true

    echo "==> [gcp-builder-async] Effective substituters:"
    nix config show 2>/dev/null | grep -E "^(substituters|trusted-public-keys)" || true

    echo "==> [gcp-builder-async] Cloning ${cfg.repoUrl}..."
    rm -rf "$WORK_DIR"
    git clone --depth 1 "${cfg.repoUrl}" "$WORK_DIR" || exit 1
    cd "$WORK_DIR" || exit 1

    echo "==> [gcp-builder-async] Fetching binary cache signing key..."
    gcloud secrets versions access latest \
      --secret="${cfg.signingKeySecret}" \
      --project="$PROJECT" > "$KEY_FILE" || exit 1
    chmod 600 "$KEY_FILE"

    OUT_PATHS=()
    for host in ${concatStringsSep " " cfg.cacheHosts}; do
      echo "==> [gcp-builder-async] Building $host toplevel..."
      out=$(nix build ".#nixosConfigurations.$host.config.system.build.toplevel" \
        --no-link --print-out-paths \
        --extra-experimental-features "nix-command flakes")
      if [ -z "$out" ]; then
        echo "==> [gcp-builder-async] WARNING: build failed for $host, skipping."
        continue
      fi
      OUT_PATHS+=("$out")
    done

    if [ ''${#OUT_PATHS[@]} -eq 0 ]; then
      echo "==> [gcp-builder-async] ERROR: nothing built, no cache to upload."
      exit 1
    fi

    # The runtime closure, plus the other outputs of everything in it.
    #
    # Copying a store path copies what it refers to at runtime, and nothing at
    # runtime refers to a `dev` output — so wpewebkit's headers never reached
    # the bucket while its `out` did, and anything compiling against WebKit
    # rebuilt the whole of it while the cache reported a hit.
    #
    # `--all` fixes that and goes much too far: it is the VM's entire store,
    # every compiler and build-only dependency it substituted along the way,
    # all of it signed and compressed before a byte is uploaded. What is wanted
    # is narrower — the packages this system is made of, with all their outputs
    # rather than just the one the system points at.
    echo "==> [gcp-builder-async] Collecting outputs of the system's closure..."
    mapfile -t CLOSURE < <(nix-store -qR "''${OUT_PATHS[@]}")
    mapfile -t DERIVERS < <(nix-store -q --deriver "''${CLOSURE[@]}" 2>/dev/null \
      | grep -v '^unknown-deriver$' | sort -u)
    ALL_OUTPUTS=("''${CLOSURE[@]}")
    if [ ''${#DERIVERS[@]} -gt 0 ]; then
      # A deriver may have been garbage collected or never existed here; its
      # outputs are simply skipped rather than failing the run.
      mapfile -t EXTRA < <(nix-store -q --outputs "''${DERIVERS[@]}" 2>/dev/null \
        | while read -r o; do [ -e "$o" ] && echo "$o"; done)
      ALL_OUTPUTS+=("''${EXTRA[@]}")
    fi

    echo "==> [gcp-builder-async] Signing and staging ''${#ALL_OUTPUTS[@]} paths into $CACHE_DIR..."
    printf '%s\n' "''${ALL_OUTPUTS[@]}" | sort -u \
      | xargs nix copy --to "file://$CACHE_DIR?secret-key=$KEY_FILE&compression=zstd" || exit 1

    # The bucket may not exist: it can be deleted, or this can be a fresh
    # project. Without this the whole build runs, finishes, and then dies on
    # the upload — three quarters of an hour of compilation thrown away on a
    # bucket that takes a second to make.
    #
    # Public read is not an oversight. Nix fetches a substituter over plain
    # HTTPS with no credentials, so a private bucket answers every request with
    # 403 and the cache is silently useless. What is in it is signed build
    # output of public packages, and the signature is what makes it
    # trustworthy, not the obscurity of the URL.
    if ! gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
      echo "==> [gcp-builder-async] Bucket gs://$BUCKET is missing; creating it..."
      gcloud storage buckets create "gs://$BUCKET" \
        --project="$PROJECT" \
        --location="''${ZONE%-*}" \
        --uniform-bucket-level-access || exit 1
      gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
        --project="$PROJECT" \
        --member=allUsers \
        --role=roles/storage.objectViewer >/dev/null || exit 1
    fi

    echo "==> [gcp-builder-async] Uploading binary cache to gs://$BUCKET..."
    gcloud storage rsync -r "$CACHE_DIR" "gs://$BUCKET" --project="$PROJECT" || exit 1

    # rsync compares by size, and narinfos are fixed-length: a re-signed one
    # (new NAR URL, new signature) is byte-identical in length to the old and
    # gets silently skipped, leaving a narinfo that points at a NAR which no
    # longer exists. Re-upload them unconditionally.
    #
    # no-store matters too: publicly readable GCS objects default to
    # Cache-Control: public, max-age=3600, so without this a client can fetch
    # an hour-stale narinfo referencing a deleted NAR and fail with a 404.
    echo "==> [gcp-builder-async] Refreshing narinfos (uncacheable)..."
    gcloud storage cp "$CACHE_DIR"/*.narinfo "gs://$BUCKET/" \
      --cache-control="no-store, max-age=0" --project="$PROJECT" || exit 1

    echo "==> [gcp-builder-async] Cache fill completed successfully."
  '';

  gcpCacheFill = pkgs.writeShellScriptBin "gcp-cache-fill" ''
    set -euo pipefail

    PROJECT="${cfg.project}"
    ZONE="${cfg.zone}"
    INSTANCE="${cfg.asyncInstanceName}"
    MACHINE_TYPE="${cfg.machineType}"
    DISK_SIZE="${cfg.diskSize}"
    GCLOUD=${pkgs.google-cloud-sdk}/bin/gcloud

    instance_exists() {
      $GCLOUD compute instances describe "$INSTANCE" \
        --zone="$ZONE" --project="$PROJECT" &>/dev/null
    }

    follow_logs() {
      echo "==> [gcp-builder] Waiting for $INSTANCE to come up..."
      until instance_exists; do sleep 5; done
      echo "==> [gcp-builder] Tailing GCP VM serial port logs ($INSTANCE)..."
      # The VM deletes itself when the build finishes, which makes tail exit
      # non-zero; that is the success path, not an error.
      $GCLOUD compute instances tail-serial-port-output "$INSTANCE" \
        --zone="$ZONE" \
        --project="$PROJECT" || true
      echo "==> [gcp-builder] Serial log ended (VM gone or preempted)."
    }

    case "''${1:-}" in
      -f | --follow | logs)
        follow_logs
        exit 0
        ;;
    esac

    if instance_exists; then
      echo "==> [gcp-builder] $INSTANCE is already running."
      echo "==> [gcp-builder] Follow progress using: gcp-cache-fill -f"
      exit 0
    fi

    echo "==> [gcp-builder] Launching GCP cache fill VM ($INSTANCE)..."
    # Run in the foreground: creation takes ~30s and previously it was
    # backgrounded with `&`, so closing the terminal SIGHUP'd it and the VM was
    # never created. Only the build itself is meant to be asynchronous.
    $GCLOUD compute instances create "$INSTANCE" \
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
      --metadata=serial-port-enable=TRUE \
      --metadata-from-file=startup-script=${gcpCacheFillScript} \
      --quiet

    echo "==> [gcp-builder] Cache fill VM launched; it self-deletes when done."
    echo "==> [gcp-builder] Follow progress using: gcp-cache-fill -f"
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
    asyncInstanceName = mkOption {
      type = types.str;
      default = "nix-builder-async";
      description = "Instance name for the oneshot gcp-cache-fill builder.";
    };
    repoUrl = mkOption {
      type = types.str;
      default = "https://github.com/codebam/nixos.git";
      description = "Flake repository the cache fill VM clones and builds.";
    };
    cacheHosts = mkOption {
      type = types.listOf types.str;
      default = [ "nixos-desktop" ];
      description = "nixosConfigurations attribute names to build and push to the cache.";
    };
    failureHoldMinutes = mkOption {
      type = types.int;
      default = 15;
      description = ''
        How long a failed cache fill VM stays alive before self-destructing, so
        its logs can be inspected over SSH. Successful runs delete immediately.
      '';
    };
    extraSubstituters = mkOption {
      type = types.listOf types.str;
      default = [ "https://nyx-cache.chaotic.cx" ];
      description = ''
        Additional substituters for the builder VM. These cannot come from a
        flake's own nixConfig: that requires an interactive accept prompt, which
        a startup script never gets, so the VM silently ignores it and rebuilds
        from source. chaotic ships firefox-nightly this way, and rebuilding it
        fails outright once Mozilla overwrites the nightly tarball its
        fixed-output hash was taken from.
      '';
    };
    extraTrustedPublicKeys = mkOption {
      type = types.listOf types.str;
      default = [ "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk=" ];
      description = "Public keys matching extraSubstituters.";
    };
    cachePublicKey = mkOption {
      type = types.str;
      default = "codebam-nix-cache-1:ZiBhSEjcy3Y53eTmQIdJsa1T1T6fCrh52EK22amzkD0=";
      description = ''
        Public half of the binary cache signing key, used by the builder VM to
        trust its own cache as a substituter. Must match the private key in the
        Secret Manager secret named by signingKeySecret.
      '';
    };
    signingKeySecret = mkOption {
      type = types.str;
      default = "nix-cache-signing-key";
      description = "GCP Secret Manager secret holding the binary cache private signing key.";
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
