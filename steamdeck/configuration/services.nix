{ config, pkgs, lib, inputs, ... }:

{
  services = {
    desktopManager.gnome.enable = true;
  };
}
