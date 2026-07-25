_: {
  # /var/log is preserved across the boot-time root wipe, and the journald
  # default cap is 10% of the filesystem -- ~100 GB on a 1 TB disk. Bound it.
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemMaxFileSize=128M
    MaxRetentionSec=1month
  '';
}
