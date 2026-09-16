{ lib, ... }:

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

    # The Deck's ESP is only 500 MB and a Lanzaboote generation can need two
    # ~65 MB initrds (main plus noCleanup), so the shared 10-generation limit
    # filled it and a switch died with ENOSPC while installing a specialisation.
    # Keep the current and two rollback generations only.
    loader.systemd-boot.configurationLimit = lib.mkForce 3;
  };
}
