{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    podman-compose
    virt-manager
    distrobox
  ];
}
