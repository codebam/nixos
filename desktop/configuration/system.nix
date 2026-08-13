{ lib, ... }:

{
  system = {
    stateVersion = "26.05";
  };

  # Keep the 2G GPT swap partition in the table (reclaiming it needs a
  # repartition) but stop activating it. zram + the btrfs swapfile remain.
  swapDevices = lib.mkForce [
    { device = "/swap/swapfile"; }
  ];
}
