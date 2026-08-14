{ pkgs, ... }:

{
  cleanupRoot = {
    enable = true;
    fsType = "bcachefs";
    devices = [
      "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HALR-000L7_S3TPNX0K805497-part3"
    ];
    extraAfter = [ "unlock-bcachefs--.service" ];
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    supportedFilesystems = [ "bcachefs" ];
    # The root filesystem is only unlocked partway through stage 1, so the
    # cleanup service has to wait for it.
    initrd.systemd.services.create-needed-for-boot-dirs.after = [ "unlock-bcachefs--.service" ];
  };
}
