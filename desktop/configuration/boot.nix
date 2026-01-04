{ pkgs, ... }:

{
  boot = {
    supportedFilesystems = [ "bcachefs" ];
    kernelPackages = pkgs.linuxPackages_xanmod_latest;
    kernelParams = [
      "usbcore.autosuspend=-1"
      "processor.max_cstate=1"
      "idle=nomwait"
      "amd_pstate=active"
    ];
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
              mount -t bcachefs /dev/disk/by-id/nvme-Sabrent_Rocket_Q_FC6207030D4501357285-part3 /bcachefs_tmp

              # If a @root subvolume exists, archive it
              if [[ -e /bcachefs_tmp/@root ]]; then
                echo "Archiving existing @root subvolume..."
                mkdir -p /bcachefs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /bcachefs_tmp/@root)" "+%Y-%m-%d_%H:%M:%S")
                mv /bcachefs_tmp/@root "/bcachefs_tmp/old_roots/$timestamp"
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

              # Create the new, clean @root subvolume for the new generation
              echo "Creating new @root subvolume..."
              bcachefs subvolume create /bcachefs_tmp/@root

              # Clean up the temporary mount
              umount /bcachefs_tmp
            '';
          };
        };
      };
    };
  };
}
