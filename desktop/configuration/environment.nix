{ pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    blender-hip
    inputs.lulu.packages.${pkgs.system}.default
  ];
}
