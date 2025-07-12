_:

{
  imports = [
    ../hardware-configuration.nix
    ./networking.nix
    ./boot.nix
    ./systemd.nix
    ./nixpkgs.nix
    ./system.nix
    ./specialisation.nix
  ];
}
