{
  disko.devices = {
    disk = {
      nixos = {
        device = "/dev/disk/by-id/nvme-Sabrent_Rocket_Q_FC6207030D4501357285";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              label = "nixos-desktop-esp";
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              label = "nixos-desktop-swap";
              size = "30G";
              format = "swap";
            };
            root = {
              label = "nixos-desktop-root";
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "impermanence_subvolumes";
              };
            };
          };
        };
      };
      bcachefs_filesystems = {
        impermanence_subvolumes = {
          type = "bcachefs_filesystem";
          passwordFile = "/tmp/secret.key";
          extraFormatArgs = [
            "--compression=lz4"
            "--background_compression=lz4"
          ];
          subvolumes = {
            "@root" = {
              mountpoint = "/";
              mountOptions = [
                "verbose"
              ];
            };
            "@nix" = {
              mountpoint = "/nix";
            };
            "@persist" = {
              mountpoint = "/persistent";
            };
          };
        };
      };
    };
  };
}
