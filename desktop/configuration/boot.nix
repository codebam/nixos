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
    # CachyOS rc kernel from chaotic-nyx (its NixOS module, imported in
    # flake.nix, supplies the overlay): desktop/gaming tuning and sched_ext
    # support instead of mainline latest.
    kernelPackages = pkgs.linuxPackages_cachyos-rc;
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
