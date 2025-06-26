{ config
, pkgs
, lib
, inputs
, ...
}:
{
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
          Experimental = true;
        };
      };
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
