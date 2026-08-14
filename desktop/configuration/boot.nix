{ pkgs, ... }:

{
  cleanupRoot = {
    enable = true;
    fsType = "btrfs";
    devices = [ "/dev/mapper/crypted" ];
    mountOptions = "defaults,compress=zstd";
    extraAfter = [
      "cryptsetup.target"
      "systemd-udev-settle.service"
      "dev-mapper-crypted.device"
    ];
    extraWants = [ "dev-mapper-crypted.device" ];
  };

  boot = {
    supportedFilesystems = [ "btrfs" ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "usbcore.autosuspend=-1"
      "amd_pstate=active"
      "amd_prefcore=enable"
      "transparent_hugepage=always"
      "split_lock_detect=off"
      "preempt=full"
    ];
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
}
