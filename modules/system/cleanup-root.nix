{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.cleanupRoot;

  # Both filesystems in use here expose the same three operations, they just
  # spell them differently.
  fsTools = {
    btrfs = {
      create = "btrfs subvolume create";
      delete = "btrfs subvolume delete --recursive";
      isSubvolume = "btrfs subvolume show";
    };
    bcachefs = {
      create = "bcachefs subvolume create";
      # bcachefs has no recursive delete; NixOS roots contain no nested
      # subvolumes, so a plain delete is enough.
      delete = "bcachefs subvolume delete";
      isSubvolume = "bcachefs subvolume show";
    };
  };
  tools = fsTools.${cfg.fsType};

  script = ''
    set -u
    log() {
      echo "[cleanup-root] $*" >&2
    }

    fail() {
      log "FATAL: $*"
      exit 1
    }

    # Fail fast if the initrd stops carrying binaries this script assumes.
    # mount/umount come from nixpkgs' own initrd extraBin (see below);
    # everything else is shadowed by extraBin entries there.
    for cmd in mount umount mkdir mv rm cat printf; do
      command -v "$cmd" >/dev/null 2>&1 || fail "missing required binary: $cmd"
    done

    MOUNT_POINT="/cleanup-root-tmp"

    log "--- Starting cleanup-root (${cfg.fsType}, mode=${cfg.mode}) ---"

    # --- 1. Find the target device ---
    device=""
    for attempt in $(seq 1 ${toString cfg.deviceTimeout}); do
      for candidate in ${lib.escapeShellArgs cfg.devices}; do
        if [[ -e "$candidate" ]]; then
          device="$candidate"
          break 2
        fi
      done
      log "Attempt $attempt: device not found, waiting 1s..."
      sleep 1
    done

    if [[ -z "$device" ]]; then
      log "ERROR: none of ${lib.escapeShellArgs cfg.devices} appeared."
      log "Available devices in /dev/disk/by-id/:"
      ls -la /dev/disk/by-id/ || true
      fail "Device discovery failed."
    fi
    log "Found device: $device"

    # --- 2. Mount the filesystem ---
    mkdir -p "$MOUNT_POINT"
    if ! mount -t ${cfg.fsType} -o ${lib.escapeShellArg cfg.mountOptions} "$device" "$MOUNT_POINT"; then
      fail "Failed to mount $device"
    fi
    log "Mounted $device at $MOUNT_POINT."

    unmount_and_fail() {
      umount "$MOUNT_POINT" || log "Warning: failed to unmount $MOUNT_POINT."
      fail "$1"
    }

    delete_subvolume() {
      local path="$1"
      # NixOS marks /var/empty immutable; the delete fails otherwise.
      if [[ -d "$path/var/empty" ]]; then
        chattr -i "$path/var/empty" || log "Warning: could not chattr -i $path/var/empty"
      fi
      ${tools.delete} "$path"
    }

    ${
      if cfg.mode == "keep" then
        ''
          # --- 3. Leave any existing root in place ---
          if [[ -e "$MOUNT_POINT/@root" ]]; then
            log "Existing @root found. No action needed."
          else
            log "No existing @root found. Creating a new one."
            ${tools.create} "$MOUNT_POINT/@root"
            [[ -d "$MOUNT_POINT/@root" ]] || unmount_and_fail "Failed to create initial @root subvolume."
            log "New @root subvolume created successfully."
          fi
        ''
      else
        ''
          # --- 3. Replace @root, keeping the old one until the new one exists ---
          archived_this_run=""
          if [[ -e "$MOUNT_POINT/@root" ]]; then
            log "Found existing @root subvolume. Preparing to replace it."
            BOOT_BACKUP_NAME="@root.bak-$(date +%s-%N)"

            log "Moving @root to $BOOT_BACKUP_NAME as a temporary backup."
            if ! mv -T -n "$MOUNT_POINT/@root" "$MOUNT_POINT/$BOOT_BACKUP_NAME" || [[ -e "$MOUNT_POINT/@root" ]]; then
              unmount_and_fail "Could not move existing @root. Aborting."
            fi

            log "Creating new @root subvolume..."
            ${tools.create} "$MOUNT_POINT/@root"

            if [[ ! -d "$MOUNT_POINT/@root" ]]; then
              log "ERROR: FAILED TO CREATE NEW @root subvolume!"
              log "Attempting to restore from backup: $BOOT_BACKUP_NAME"
              if mv "$MOUNT_POINT/$BOOT_BACKUP_NAME" "$MOUNT_POINT/@root"; then
                log "SUCCESS: Restored previous @root. System will boot with the old root."
                umount "$MOUNT_POINT"
                exit 0
              else
                unmount_and_fail "Could not restore backup. NO @root EXISTS."
              fi
            fi

            log "New @root subvolume created successfully."
            log "Moving temporary backup to long-term storage."
            pending="$MOUNT_POINT/old_roots/.pending-$BOOT_BACKUP_NAME"
            if mkdir -p "$MOUNT_POINT/old_roots" && \
              mv -T -n "$MOUNT_POINT/$BOOT_BACKUP_NAME" "$pending" && \
              [[ ! -e "$MOUNT_POINT/$BOOT_BACKUP_NAME" ]]; then
              # Only a complete, matching sidecar makes an archive eligible for
              # deletion. An interrupted move or write therefore keeps the root.
              if archive_id=$(date +%s-%N) && [[ "$archive_id" =~ ^[1-9][0-9]{0,9}-[0-9]{9}$ ]]; then
                archive="$MOUNT_POINT/old_roots/archive-$archive_id"
                marker="$archive.archive-time"
                if [[ ! -e "$archive" && ! -e "$marker" && ! -e "$marker.tmp" ]] && \
                  mv -T -n "$pending" "$archive" && [[ ! -e "$pending" ]]; then
                  archived_this_run="$archive"
                  if ! { printf '%s\n' "$archive_id" > "$marker.tmp" && \
                    mv -T -n "$marker.tmp" "$marker" && [[ ! -e "$marker.tmp" ]]; }; then
                    log "Warning: Could not record archive time for $archive; keeping it."
                  fi
                else
                  log "Warning: Could not name archived root $pending; keeping it."
                fi
              else
                log "Warning: Could not determine archive time for $pending; keeping it."
              fi
            else
              log "Warning: Could not move backup to old_roots; keeping it."
            fi
          else
            log "No existing @root found. Creating a new one."
            ${tools.create} "$MOUNT_POINT/@root"
            [[ -d "$MOUNT_POINT/@root" ]] || unmount_and_fail "Failed to create initial @root subvolume."
            log "New @root subvolume created successfully."
          fi

          # --- 4. Non-critical cleanup of old roots ---
          # Directory mtimes predate archival and can change afterwards. Legacy
          # archives and incomplete or invalid sidecars have unknown age: keep them.
          (
            if [[ -d "$MOUNT_POINT/old_roots" ]]; then
              now=$(date +%s)
              [[ "$now" =~ ^[1-9][0-9]{0,9}$ ]] || exit 1
              cutoff=$(( now - ${toString cfg.keepDays} * 24 * 60 * 60 ))
              log "Deleting old roots older than ${toString cfg.keepDays} days."
              find "$MOUNT_POINT/old_roots/" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r old_root; do
                # A clock jump during this run must not delete its new archive.
                [[ "$old_root" != "$archived_this_run" ]] || continue
                name="''${old_root##*/}"
                [[ "$name" =~ ^archive-([1-9][0-9]{0,9})-([0-9]{9})$ ]] || continue
                archive_time="''${BASH_REMATCH[1]}"
                archive_id="''${name#archive-}"
                marker="$old_root.archive-time"
                [[ -f "$marker" && ! -L "$marker" ]] || continue
                # Bash command substitution strips NULs, so reject them first.
                if IFS= read -r -d "" ignored < "$marker"; then continue; fi
                recorded=$(cat "$marker" && printf '.') || continue
                [[ "$recorded" == "$archive_id"$'\n.' ]] || continue
                if (( archive_time < cutoff )); then
                  log "Deleting old root: $old_root"
                  if ${tools.isSubvolume} "$old_root" &>/dev/null; then
                    delete_subvolume "$old_root"
                  else
                    log "Warning: $old_root is not a subvolume, removing with rm -rf"
                    [[ -d "$old_root/var/empty" ]] && chattr -i "$old_root/var/empty" || true
                    rm -rf "$old_root"
                  fi
                  # Keep the sidecar if deletion failed, so a later run can retry.
                  if [[ ! -e "$old_root" ]]; then
                    rm -f "$marker"
                  fi
                fi
              done
            fi
          ) || log "Warning: cleanup of old roots failed. Continuing..."
        ''
    }

    # --- 5. Finalize ---
    umount "$MOUNT_POINT"
    log "--- cleanup-root completed successfully ---"
  '';
in
{
  # One implementation of the stage-1 "wipe / on every boot" dance, which was
  # previously copy-pasted across three hosts and three specialisations and had
  # already drifted (different timestamp formats, two different old-root GC
  # strategies, one of which needed gawk smuggled into the initrd).
  options.cleanupRoot = {
    enable = lib.mkEnableOption "wiping and recreating the @root subvolume in stage 1";

    devices = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      description = "Candidate paths to the filesystem holding @root; the first that appears wins.";
    };

    fsType = lib.mkOption {
      type = lib.types.enum (lib.attrNames fsTools);
      description = "Filesystem holding the @root subvolume.";
    };

    mountOptions = lib.mkOption {
      type = lib.types.str;
      default = "defaults";
      description = "Options for the temporary stage-1 mount.";
    };

    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "How long archived roots are kept under old_roots.";
    };

    deviceTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Seconds to wait for one of `devices` to appear.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "wipe"
        "keep"
      ];
      default = "wipe";
      description = ''
        `wipe` archives the current @root and boots into a fresh one.
        `keep` reuses the existing @root, creating one only if absent. The
        noCleanup specialisation on each host flips this.
      '';
    };

    extraAfter = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional units cleanup-root must run after (unlock/device units).";
    };

    extraWants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional units cleanup-root pulls in.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Boot entry that keeps the current root instead of archiving it -- useful
    # when something in /etc or /var needs to survive one more boot. Defined
    # once here rather than copy-pasted into every host.
    specialisation.noCleanup.configuration.cleanupRoot.mode = "keep";

    boot.initrd.systemd = {
      # The script uses seq/sleep/find/date/ls/mv in stage 1; only
      # chattr used to be wired in, the rest relied on whatever the initrd
      # happened to carry. mount/umount/fsck/less already come from
      # nixpkgs' own initrd extraBin, so only the missing ones are added.
      extraBin = {
        chattr = "${pkgs.busybox}/bin/chattr";
        seq = "${pkgs.coreutils}/bin/seq";
        sleep = "${pkgs.coreutils}/bin/sleep";
        find = "${pkgs.findutils}/bin/find";
        date = "${pkgs.coreutils}/bin/date";
        ls = "${pkgs.coreutils}/bin/ls";
        mv = "${pkgs.coreutils}/bin/mv";
      };

      services = {
        # The new root has to exist before NixOS populates it.
        create-needed-for-boot-dirs = {
          after = [ "cleanup-root.service" ];
          serviceConfig.KeyringMode = "inherit";
        };

        cleanup-root = {
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            KeyringMode = "inherit";
          };
          requiredBy = [ "initrd.target" ];
          after = [ "local-fs-pre.target" ] ++ cfg.extraAfter;
          wants = cfg.extraWants;
          before = [ "sysroot.mount" ];
          inherit script;
        };
      };
    };
  };
}
