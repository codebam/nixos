{ config, pkgs, lib, inputs, ... }:
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
    # Enable firmware updates
    enableRedistributableFirmware = true;
    # Enable CPU microcode updates
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
