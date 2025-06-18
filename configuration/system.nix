{ config, pkgs, lib, inputs, ... }:
{
  system = {
    switch = {
      enableNg = true;
    };
  };
}
