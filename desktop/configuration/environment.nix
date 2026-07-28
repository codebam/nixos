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
    # The rewrite rather than the C build. Both install a binary called
    # `viewport` and would collide; the C one stays a flake input because the
    # portal routing below still comes from it.
    inputs.viewport-smithay.packages.${pkgs.stdenv.hostPlatform.system}.viewport-smithay
  ];
}
