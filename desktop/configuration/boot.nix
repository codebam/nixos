{ pkgs, ... }:

{
  boot = {
    plymouth = {
      enable = true;
    };
    supportedFilesystems = [ "bcachefs" ];
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      systemd = {
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
              mkdir -p /bcachefs_tmp
              mount -t bcachefs /dev/disk/by-id/nvme-Sabrent_Rocket_Q_FC6207030D4501357285-part3 /bcachefs_tmp
              if [[ -e /bcachefs_tmp/@root ]]; then
                mkdir -p /bcachefs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /bcachefs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
                mv /bcachefs_tmp/@root "/bcachefs_tmp/old_roots/$timestamp"
              fi

              delete_subvolume_recursively() {
                IFS=$'\n'
                for i in $(bcachefs subvolume list -o "$1" | cut -f 2- -d ' '); do
                  delete_subvolume_recursively "/bcachefs_tmp/$i"
                done
                bcachefs subvolume delete "$1"
              }

              for i in $(find /bcachefs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
                delete_subvolume_recursively "$i"
              done

              bcachefs subvolume create /bcachefs_tmp/@root
              umount /bcachefs_tmp
            '';
          };
        };
      };
    };
  };
}
