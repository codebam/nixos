{ lib, ... }:

{
  system = {
    stateVersion = "26.05";
  };
  # systemd.user.services.steamos-manager.after = [ "cecd.service" ];

  # 2G GPT swap partition stays on disk; stop activating it. Keep the
  # btrfs swapfile that disko still creates under /swap.
  swapDevices = lib.mkForce [
    { device = "/swap/swapfile"; }
  ];
}
