{ lib, ... }:

{
  system = {
    stateVersion = "26.05";
  };

  # 8G GPT swap partition stays on disk; stop activating it. zram remains.
  swapDevices = lib.mkForce [ ];
}
