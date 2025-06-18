{ config, pkgs, lib, inputs, ... }:

{
  services = {
    mako = {
      enable = true;
      settings = {
        layer = "overlay";
      };
    };
  };
}
