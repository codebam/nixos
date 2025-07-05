{ pkgs, ... }:
{
  boot = {
    initrd = {
      systemd = {
        services = {
          create-needed-for-boot-dirs = {
            after = [
              "cleanup-root.service"
            ];
            serviceConfig.KeyringMode = "inherit";
          };
          cleanup-root = {
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
            serviceConfig.KeyringMode = "inherit";
            requiredBy = [ "initrd.target" ];
            after = [
              "local-fs-pre.target"
              "systemd-udev-settle.service"
            ];
            before = [ "sysroot.mount" ];
            path = [ pkgs.btrfs-progs ];
            script = ''
              set -euo pipefail

              log() {
                echo "[cleanup-root] $*" >&2
              }

              fail() {
                log "FATAL: $*"
                # Keep the initrd running for 5 minutes for debugging
                sleep 300
                exit 1
              }

              log "--- Starting cleanup-root service ---"

              DEVICE_PATH="/dev/disk/by-id/nvme-Micron_2500_MTFDKBK1T0QGN_25024D7C572C-part3"
              FALLBACK_DEVICE="/dev/nvme0n1p3"
              ACTUAL_DEVICE=""

              log "Waiting for device to become available..."
              for attempt in {1..30}; do
                udevadm settle

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

              MOUNT_POINT="/btrfs_tmp"
              mkdir -p "$MOUNT_POINT"

              log "Mounting btrfs filesystem from $ACTUAL_DEVICE to $MOUNT_POINT"
              if ! mount -t btrfs -o "defaults,compress=zstd" "$ACTUAL_DEVICE" "$MOUNT_POINT"; then
                fail "Failed to mount $ACTUAL_DEVICE"
              fi
              log "Mount successful."

              if [[ -e "$MOUNT_POINT/@root" ]]; then
                log "Found existing @root subvolume. Preparing to replace it."
                
                # Create a temporary backup name for this specific boot operation
                # This makes it easy to restore if the next step fails.
                BOOT_BACKUP_NAME="@root.bak-$(date +%s)"
                
                log "Moving @root to $BOOT_BACKUP_NAME as a temporary backup."
                if ! mv "$MOUNT_POINT/@root" "$MOUNT_POINT/$BOOT_BACKUP_NAME"; then
                    # If we can't even move the old root, something is seriously wrong.
                    umount "$MOUNT_POINT" || log "Warning: Failed to unmount $MOUNT_POINT on failure."
                    fail "Could not move existing @root. Aborting."
                fi

                log "Creating new @root subvolume..."
                btrfs subvolume create "$MOUNT_POINT/@root"

                # *** CRITICAL CHECK AND RESTORE LOGIC ***
                if [[ ! -d "$MOUNT_POINT/@root" ]]; then
                  log "ERROR: FAILED TO CREATE NEW @root subvolume!"
                  log "Attempting to restore from backup: $BOOT_BACKUP_NAME"
                  
                  if mv "$MOUNT_POINT/$BOOT_BACKUP_NAME" "$MOUNT_POINT/@root"; then
                    log "SUCCESS: Restored previous @root. System will boot with the old root."
                    # We exit with 0 because we successfully restored a valid state.
                    # The system can boot, even though it's not a fresh state.
                    umount "$MOUNT_POINT"
                    log "--- cleanup-root service finished with a restored root ---"
                    exit 0
                  else
                    # This is a disaster scenario. We have no @root and couldn't restore it.
                    umount "$MOUNT_POINT" || log "Warning: Failed to unmount $MOUNT_POINT on final failure."
                    fail "Could not restore backup. Filesystem is in an inconsistent state. NO @root EXISTS."
                  fi
                else
                  log "New @root subvolume created successfully."
                  # Now that we have a new, valid @root, we can archive the backup.
                  log "Moving temporary backup to long-term storage."
                  mkdir -p "$MOUNT_POINT/old_roots"
                  # Use the modification time of the original subvolume for the archive name
                  timestamp=$(date --date="@$(stat -c %Y "$MOUNT_POINT/$BOOT_BACKUP_NAME")" "+%Y-%m-%d_%H-%M-%S")
                  mv "$MOUNT_POINT/$BOOT_BACKUP_NAME" "$MOUNT_POINT/old_roots/$timestamp" || log "Warning: Could not move backup to old_roots."
                fi
              else
                log "No existing @root found. Creating a new one."
                btrfs subvolume create "$MOUNT_POINT/@root"
                if [[ ! -d "$MOUNT_POINT/@root" ]]; then
                    umount "$MOUNT_POINT" || log "Warning: Failed to unmount $MOUNT_POINT on failure."
                    fail "Failed to create initial @root subvolume."
                fi
                log "New @root subvolume created successfully."
              fi

              (
                log "Starting non-critical cleanup of old subvolumes (older than 30 days)."
                if [[ -d "$MOUNT_POINT/old_roots" ]]; then
                  delete_subvolume_recursively() {
                    local subvol_path="$1"
                    log "Deleting subvolume: $subvol_path"
                    local nested_subvols
                    nested_subvols=$(btrfs subvolume list -o "$subvol_path" | awk '{print $9}')
                    for i in $nested_subvols; do
                      delete_subvolume_recursively "$MOUNT_POINT/$i"
                    done
                    btrfs subvolume delete "$subvol_path"
                  }
                  
                  find "$MOUNT_POINT/old_roots/" -mindepth 1 -mtime +30 -type d | while read -r old_subvol; do
                      log "Found old backup to delete: $old_subvol"
                      if btrfs subvolume show "$old_subvol" &>/dev/null; then
                          delete_subvolume_recursively "$old_subvol"
                      else
                          log "Warning: $old_subvol is not a btrfs subvolume, removing with rm -rf"
                          rm -rf "$old_subvol"
                      fi
                  done
                fi
                log "Non-critical cleanup finished."
              ) || log "Warning: Non-critical cleanup of old roots encountered an error. Continuing..."

              log "Unmounting btrfs filesystem..."
              umount "$MOUNT_POINT"

              log "--- cleanup-root service completed successfully ---"
            '';
          };
        };
      };
    };
  };
}
