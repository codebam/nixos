{ pkgs, inputs, ... }:

{
  # The portal routing lives with the compositor, since a version of it that
  # only exists here would have to be rediscovered by anyone else using the
  # flake. Without it screen sharing fails with nothing in any log naming a
  # portal: the ScreenCast interface is never exposed at all.
  imports = [ inputs.viewport.nixosModules.portal ];
  programs.viewport.portals.enable = true;

  environment.systemPackages = with pkgs; [
    cargo
    gcc
    awakened-poe-trade
    # blender-hip
    # inputs.steel.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.lulu.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.viewport.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
