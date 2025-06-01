{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

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
              mount -t btrfs /dev/disk/by-id/nvme-Micron_2500_MTFDKBK1T0QGN_25024D7C572C-part3 /btrfs_tmp
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

  systemd = {
    services = {
      systemd-remount-fs = {
        enable = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    maliit-keyboard
    maliit-framework
  ];

  networking = {
    hostName = "nixos-steamdeck";
  };

  jovian = {
    steam = {
      enable = true;
      user = "codebam";
      autoStart = true;
      desktopSession = "plasma";
    };
    devices = {
      steamdeck = {
        enable = true;
      };
    };
    steamos = {
      useSteamOSConfig = true;
    };
  };

  environment.etc."kio/servicemenus/steam.desktop".text = ''
    [Desktop Entry]
    Type=Service
    ServiceTypes=KonqPopupMenu/Plugin
    MimeType=application/x-desktop;application/x-executable;text/plain;
    Actions=openInSteam
    X-KDE-Priority=TopLevel
    Icon=steam

    [Desktop Action openInSteam]
    Name=Open with Steam
    Icon=steam
    Exec=${pkgs.steam}/bin/steam %u
  '';

  system = {
    stateVersion = "23.11";
  };
}
