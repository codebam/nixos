{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mullvad-vpn
    podman-compose
    virt-manager
    distrobox
  ];
}
