_: {
  # These used to live in desktop/hardware-configuration.nix, which
  # nixos-generate-config overwrites and statix.toml excludes from linting.
  # Host-specific networking sysctls (forwarding, rp_filter, low port range)
  # stay next to the NAT rules in desktop/configuration/networking.nix.
  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;

    "net.core.default_qdisc" = "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";

    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 512;
  };
}
