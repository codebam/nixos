{ pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    cargo
    gcc
    # blender-hip
    # inputs.steel.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.lulu.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
