{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    blender-hip
  ];
}
