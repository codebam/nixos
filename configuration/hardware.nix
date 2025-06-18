{ config, pkgs, lib, inputs, ... }:
{
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    uinput.enable = true;
    graphics = {
      enable = true;
    };
    keyboard.qmk.enable = true;
  };
}
