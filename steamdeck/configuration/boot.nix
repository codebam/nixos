_:

{
  cleanupRoot = {
    enable = true;
    fsType = "btrfs";
    devices = [
      "/dev/disk/by-id/nvme-Micron_2500_MTFDKBK1T0QGN_25024D7C572C-part3"
      "/dev/nvme0n1p3"
    ];
    mountOptions = "defaults,compress=zstd";
    extraAfter = [ "systemd-udev-settle.service" ];
  };

  boot = {
    supportedFilesystems = [ "btrfs" ];
  };
}
