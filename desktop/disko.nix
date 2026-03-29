{
  disko.devices = {
    disk = {
      nixos = {
        device = "/dev/disk/by-id/nvme-Patriot_P400L_1000GB_P400LZDCB25091507418";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            esp = {
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
              size = "2G";
              content = {
                type = "swap";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                extraFormatArgs = [ "--key-file /tmp/secret.key" ];
                settings = {
                  keyFile = "/tmp/secret.key";
                  allowDiscards = true;
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/@root" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/";
                    };
                    "/@nix" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/nix";
                    };
                    "/@persist" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/persistent";
                    };
                    "/@swap" = {
                      mountpoint = "/swap";
                      swap = {
                        swapfile.size = "2G";
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persistent".neededForBoot = true;
}
