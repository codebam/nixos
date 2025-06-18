{ config, pkgs, lib, inputs, ... }:

{
  nixpkgs.config.rocmSupport = true;
  nixpkgs.overlays = [ (final: prev: { }) ];
}
