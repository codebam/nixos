_:
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
    };
    keyboard.qmk.enable = true;
    enableRedistributableFirmware = true;
  };
}
