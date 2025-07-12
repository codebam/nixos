_: {
  specialisation = {
    noCleanup.configuration = {
      boot.initrd.systemd.services.cleanup-root = {
        enable = false;
      };
      boot.initrd.systemd.services.set-root = {
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

          # If a @root subvolume exists, exit early
          if [[ -e /bcachefs_tmp/@root ]]; then
            exit 0
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
}
