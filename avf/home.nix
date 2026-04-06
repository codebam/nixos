{ pkgs, lib, ... }:

{
  home = {
    packages = with pkgs; lib.mkForce [
      helix
    ];
  };

  programs = {
    git = {
      # signing = {
      #   key = "0271B12CCF0A185B01EB25FA4B1C30CAAB93976B";
      #   signByDefault = true;
      # };
    };
  };
}
