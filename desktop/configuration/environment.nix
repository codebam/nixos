{ pkgs, inputs, ... }:

{
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
