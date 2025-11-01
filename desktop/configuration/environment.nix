{ pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    cargo
    gcc
    blender-hip
    inputs.steel.packages.${pkgs.system}.default
    inputs.lulu.packages.${pkgs.system}.default
  ];
}
