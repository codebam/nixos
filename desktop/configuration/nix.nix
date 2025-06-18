{ config, pkgs, lib, inputs, ... }:

{
  nix = {
    settings = {
      trusted-users = [
        "makano"
      ];
    };
  };
}
