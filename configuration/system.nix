{ config
, pkgs
, lib
, inputs
, ...
}:
{
  system = {
    switch = {
      enableNg = true;
    };
    rebuild = {
      enableNg = true;
    };
  };
}
