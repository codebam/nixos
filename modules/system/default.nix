_: {
  system = {
    etc.overlay.enable = true;
    etc.overlay.mutable = true;
  };
  services.userborn.enable = true;

  # The CachyOS kernel sets CONFIG_OVERLAY_FS_INDEX=y, so overlayfs defaults to
  # index=on, which enables exclusive upperdir protection. When switching
  # configurations, the `etc` activation script mounts a *second* overlay reusing
  # upperdir=/.rw-etc/upper before moving it beneath the live /etc, and the kernel
  # rejects that with EBUSY ("upperdir is in-use as upperdir/workdir of another
  # mount"). The script then blindly runs `umount --lazy --recursive /etc`, which
  # detaches the real /etc and breaks the rest of activation until reboot.
  # Stock nixpkgs kernels build with CONFIG_OVERLAY_FS_INDEX=n, so restore that
  # default. Only the default changes; mounts asking for index=on still get it.
  boot.kernelParams = [ "overlay.index=off" ];
}
