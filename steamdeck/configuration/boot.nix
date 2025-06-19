{ config
, pkgs
, lib
, inputs
, ...
}:

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
            script = ''
              set -euo pipefail

              # Function to log messages
              log() {
                echo "[cleanup-root] $*" >&2
              }

              log "Starting cleanup-root service"

              # Wait for the NVMe device to be available
              DEVICE_PATH="/dev/disk/by-id/nvme-Micron_2500_MTFDKBK1T0QGN_25024D7C572C-part3"
              FALLBACK_DEVICE="/dev/nvme0n1p3"
              ACTUAL_DEVICE=""

              log "Waiting for device to become available..."

              # Try the by-id path first, with fallback to direct device path
              for attempt in {1..30}; do
                if [[ -e "$DEVICE_PATH" ]]; then
                  ACTUAL_DEVICE="$DEVICE_PATH"
                  log "Found device at: $ACTUAL_DEVICE"
                  break
                elif [[ -e "$FALLBACK_DEVICE" ]]; then
                  ACTUAL_DEVICE="$FALLBACK_DEVICE"
                  log "Found device at fallback path: $ACTUAL_DEVICE"
                  break
                else
                  log "Attempt $attempt: Device not found, waiting..."
                  sleep 1
                fi
              done

              if [[ -z "$ACTUAL_DEVICE" ]]; then
                log "ERROR: Could not find NVMe device after 30 attempts"
                log "Available devices:"
                ls -la /dev/disk/by-id/ || true
                ls -la /dev/nvme* || true
                exit 1
              fi

              log "Using device: $ACTUAL_DEVICE"

              # Create mount point and mount the btrfs filesystem
              mkdir -p /btrfs_tmp

              log "Mounting btrfs filesystem..."
              if ! mount -t btrfs "$ACTUAL_DEVICE" /btrfs_tmp; then
                log "ERROR: Failed to mount $ACTUAL_DEVICE"
                exit 1
              fi

              log "Successfully mounted btrfs filesystem"

              # Handle existing @root subvolume
              if [[ -e /btrfs_tmp/@root ]]; then
                log "Found existing @root subvolume, moving to old_roots"
                mkdir -p /btrfs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
                mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$timestamp"
                log "Moved @root to old_roots/$timestamp"
              fi

              # Function to recursively delete subvolumes
              delete_subvolume_recursively() {
                local subvol="$1"
                log "Deleting subvolume: $subvol"
                IFS=$'\n'
                for i in $(btrfs subvolume list -o "$subvol" | awk '{print $9}'); do
                  delete_subvolume_recursively "/btrfs_tmp/$i"
                done
                btrfs subvolume delete "$subvol"
              }

              # Clean up old root subvolumes (older than 30 days)
              log "Cleaning up old root subvolumes..."
              if [[ -d /btrfs_tmp/old_roots ]]; then
                for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30 -type d); do
                  if [[ "$i" != "/btrfs_tmp/old_roots" ]]; then
                    log "Deleting old subvolume: $i"
                    delete_subvolume_recursively "$i"
                  fi
                done
              fi

              # Create new @root subvolume
              log "Creating new @root subvolume..."
              btrfs subvolume create /btrfs_tmp/@root

              log "Unmounting btrfs filesystem..."
              umount /btrfs_tmp

              log "cleanup-root service completed successfully"
            '';
          };
        };
      };
    };
  };
}
