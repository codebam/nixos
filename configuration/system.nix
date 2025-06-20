{ config
, pkgs
, lib
, inputs
, ...
}:
{
  system = {
    rebuild = {
      enableNg = true;
    };
  };
}
