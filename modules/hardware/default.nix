{ pkgs, ... }:
{
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    uinput.enable = true;
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
      ];
    };
    keyboard.qmk.enable = true;
    enableRedistributableFirmware = true;
  };
}
