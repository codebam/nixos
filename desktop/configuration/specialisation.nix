_: {
  specialisation.noCleanup.configuration = {
    # Disable the standard cleanup service
    boot.initrd.systemd.services.cleanup-root.enable = false;

    # Define the custom set-root service
    boot.initrd.systemd.services.set-root = {
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      serviceConfig.KeyringMode = "inherit";
      requiredBy = [ "initrd.target" ];
      after = [ "local-fs-pre.target" ];
      before = [ "sysroot.mount" ];
      
      script = ''
        log() {
          echo "[cleanup-root] $*" >&2
        }

        fail() {
          log "FATAL: $*"
          exit 1
        }

        log "--- Starting no-cleanup-root service ---"

        # --- 1. Find the target device ---
        DEVICE_PATH="/dev/mapper/crypted"
        FALLBACK_DEVICE="/dev/mapper/crypted"
        ACTUAL_DEVICE=""

        log "Waiting for device to become available..."
        for attempt in {1..30}; do
          if [[ -e "$DEVICE_PATH" ]]; then
            ACTUAL_DEVICE="$DEVICE_PATH"
            break
          elif [[ -e "$FALLBACK_DEVICE" ]]; then
            ACTUAL_DEVICE="$FALLBACK_DEVICE"
            break
          else
            log "Attempt $attempt: Device not found, waiting 1s..."
            sleep 1
          fi
        done

        if [[ -z "$ACTUAL_DEVICE" ]]; then
          log "ERROR: Could not find NVMe device after 30 attempts."
          log "Available devices in /dev/disk/by-id/:"
          ls -la /dev/disk/by-id/ || true
          log "Available devices in /dev/:"
          ls -la /dev/nvme* || true
          fail "Device discovery failed."
        fi

        log "Found device: $ACTUAL_DEVICE"

        # --- 2. Mount the filesystem ---
        MOUNT_POINT="/btrfs_tmp"
        mkdir -p "$MOUNT_POINT"

        log "Mounting btrfs filesystem from $ACTUAL_DEVICE to $MOUNT_POINT"
        if ! mount -t btrfs -o "defaults,compress=zstd" "$ACTUAL_DEVICE" "$MOUNT_POINT"; then
          fail "Failed to mount $ACTUAL_DEVICE"
        fi
        log "Mount successful."

        # --- 3. Safely replace @root subvolume ---
        if [[ -e "$MOUNT_POINT/@root" ]]; then
          log "Existing @root found. No action needed."
        else
          log "No existing @root found. Creating a new one."
          btrfs subvolume create "$MOUNT_POINT/@root"
          if [[ ! -d "$MOUNT_POINT/@root" ]]; then
            umount "$MOUNT_POINT" || log "Warning: Failed to unmount $MOUNT_POINT on failure."
            fail "Failed to create initial @root subvolume."
          fi
          log "New @root subvolume created successfully."
        fi

        # --- 4. Finalize ---
        log "Unmounting btrfs filesystem..."
        umount "$MOUNT_POINT"

        log "--- no-cleanup-root service completed successfully ---"
      '';
    };
  };
}
