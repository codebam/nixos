_: {
  # These used to live in desktop/hardware-configuration.nix, which
  # nixos-generate-config overwrites and statix.toml excludes from linting.
  # Host-specific networking sysctls (forwarding, rp_filter, low port range)
  # stay next to the NAT rules in desktop/configuration/networking.nix.
  boot.kernel.sysctl = {
    # 16 (sync) only: 1 allows all magic SysRq keys (remount-ro, kill,
    # reboot) to any local console user. Sync-only still lets a hung
    # desktop flush filesystems without handing out reboot/kill.
    "kernel.sysrq" = 16;

    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";

    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };
}
