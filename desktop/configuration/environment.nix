{ pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    inputs.steel.packages.${pkgs.system}.default
    blender-hip
    inputs.lulu.packages.${pkgs.system}.default
  ];
}
