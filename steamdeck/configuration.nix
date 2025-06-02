{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "192.168.0.12";
        system = "x86_64-linux,i686-linux";
        maxJobs = 15;
        speedFactor = 4;
        supportedFeatures = [ "big-parallel" ];
        sshUser = "codebam";
        sshKey = "/home/codebam/.ssh/id_ed25519";
      }
    ];
    settings = {
      max-jobs = 0;
    };
  };

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

  systemd = {
    user = {
      # services = {
      #   steamos-manager = {
      #     enable = false;
      #     wantedBy = [ ];
      #     serviceConfig = {
      #       ExecStart = "/usr/bin/env true";
      #     };
      #   };
      # };
    };
    services = {
      systemd-remount-fs = {
        enable = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    protonup-qt
    maliit-keyboard
    maliit-framework
    (wrapRetroArch {
      cores = with libretro; [
        genesis-plus-gx # Sega
        snes9x # SNES
        beetle-psx-hw # PlayStation
        dolphin # GameCube / Wii
        stella # Atari 2600
        mame # MAME
        neocd # Neo ?
        fbneo # Neo ?
        mupen64plus # Nintendo 64
        nestopia # Nintendo NES
        mgba # Game Boy Advance
        fuse # ZX Spectrum
      ];
    })
  ];

  networking = {
    hostName = "nixos-steamdeck";
  };

  jovian = {
    decky-loader = {
      enable = true;
      user = "codebam";
    };
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

  system = {
    stateVersion = "23.11";
  };
}
