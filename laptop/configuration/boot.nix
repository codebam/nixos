{ pkgs, ... }:

{
  boot = {
    kernelPackages = pkgs.linuxPackages_cachyos;
    supportedFilesystems = [ "bcachefs" ];
    initrd = {
      systemd = {
        extraBin = {
          chattr = "${pkgs.busybox}/bin/chattr";
        };
        services = {
          create-needed-for-boot-dirs = {
            after = [
              "unlock-bcachefs--.service"
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
              "unlock-bcachefs--.service"
              "local-fs-pre.target"
            ];
            before = [ "sysroot.mount" ];
            script = ''
              # Mount the bcachefs filesystem to a temporary location
              mkdir -p /bcachefs_tmp
              mount -t bcachefs /dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HALR-000L7_S3TPNX0K805497-part3 /bcachefs_tmp

              # If a @root subvolume exists, prepare to replace it
              if [[ -e /bcachefs_tmp/@root ]]; then
                echo "Found existing @root subvolume. Preparing to replace it."
                
                BOOT_BACKUP_NAME="@root.bak-$(date +%s)"
                
                echo "Moving @root to $BOOT_BACKUP_NAME as a temporary backup."
                if ! mv /bcachefs_tmp/@root "/bcachefs_tmp/$BOOT_BACKUP_NAME"; then
                    umount /bcachefs_tmp
                    echo "FATAL: Could not move existing @root. Aborting."
                    exit 1
                fi

                echo "Creating new @root subvolume..."
                bcachefs subvolume create /bcachefs_tmp/@root

                if [[ ! -d /bcachefs_tmp/@root ]]; then
                  echo "ERROR: FAILED TO CREATE NEW @root subvolume!"
                  echo "Attempting to restore from backup: $BOOT_BACKUP_NAME"
                  
                  if mv "/bcachefs_tmp/$BOOT_BACKUP_NAME" /bcachefs_tmp/@root; then
                    echo "SUCCESS: Restored previous @root. System will boot with the old root."
                    umount /bcachefs_tmp
                    exit 0
                  else
                    umount /bcachefs_tmp
                    echo "FATAL: Could not restore backup. Filesystem is in an inconsistent state. NO @root EXISTS."
                    exit 1
                  fi
                else
                  echo "New @root subvolume created successfully."
                  echo "Moving temporary backup to long-term storage."
                  mkdir -p /bcachefs_tmp/old_roots
                  timestamp=$(date --date="@$(stat -c %Y "/bcachefs_tmp/$BOOT_BACKUP_NAME")" "+%Y-%m-%d_%H:%M:%S")
                  mv "/bcachefs_tmp/$BOOT_BACKUP_NAME" "/bcachefs_tmp/old_roots/$timestamp" || echo "Warning: Could not move backup to old_roots."
                fi
              else
                echo "No existing @root found. Creating a new one."
                bcachefs subvolume create /bcachefs_tmp/@root
                if [[ ! -d /bcachefs_tmp/@root ]]; then
                    umount /bcachefs_tmp
                    echo "FATAL: Failed to create initial @root subvolume."
                    exit 1
                fi
                echo "New @root subvolume created successfully."
              fi

              # Clean up archived roots older than 30 days
              if [[ -d /bcachefs_tmp/old_roots ]]; then
                echo "Checking for old roots to clean up..."
                # Get the current time and the cutoff time (30 days ago) in seconds since epoch
                cutoff_date_sec=$(date -d "30 days ago" +%s)

                # Use a subshell to safely change directory
                (
                  cd /bcachefs_tmp/old_roots || exit 1
                  for old_root_dir in *; do
                    # Ensure we are only looking at directories (our snapshots)
                    if [[ -d "$old_root_dir" ]]; then
                      # The directory name is a timestamp. Convert it to seconds since epoch.
                      # 'date' can parse "YYYY-MM-DD HH:MM:SS", so we replace the underscore.
                      dir_timestamp_str="''${old_root_dir//_/' '}"
                      dir_date_sec=$(date -d "$dir_timestamp_str" +%s)

                      # If the directory's date is before our cutoff date, delete it
                      if (( dir_date_sec < cutoff_date_sec )); then
                      echo "Preparing to delete old root snapshot: $old_root_dir"
                      
                      echo "Recursively removing immutable flag from $old_root_dir..."
                      chattr -R -i "/bcachefs_tmp/old_roots/$old_root_dir"
                      
                      echo "Deleting subvolume: $old_root_dir"
                      bcachefs subvolume delete "/bcachefs_tmp/old_roots/$old_root_dir"
                      fi
                    fi
                  done
                )
              fi

              # Clean up the temporary mount
              umount /bcachefs_tmp
            '';
          };
        };
      };
    };
  };
}
