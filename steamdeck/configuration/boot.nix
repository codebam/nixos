{ config, pkgs, lib, inputs, ... }:

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
            ];
            before = [ "sysroot.mount" ];
            script = ''
              mkdir -p /btrfs_tmp
              mount -t btrfs /dev/nvme0n1p3 /btrfs_tmp
              if [[ -e /btrfs_tmp/@root ]]; then
                mkdir -p /btrfs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
                mv /btrfs_tmp/@root "/btrfs_tmp/old_roots/$timestamp"
              fi

              delete_subvolume_recursively() {
                IFS=$'\n'
                for i in $(btrfs subvolume list -o "$1" | awk '{print $9}'); do
                  delete_subvolume_recursively "/btrfs_tmp/$i"
                done
                btrfs subvolume delete "$1"
              }

              for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
                delete_subvolume_recursively "$i"
              done

              btrfs subvolume create /btrfs_tmp/@root
              umount /btrfs_tmp
            '';
          };
        };
      };
    };
  };
}
