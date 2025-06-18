{ config, pkgs, lib, inputs, ... }:

{
  nixpkgs.overlays = [ (final: prev: { }) ];
}
