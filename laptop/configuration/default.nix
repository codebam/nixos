_:

{
  imports = [
    ../hardware-configuration.nix
    ./networking.nix
    ./boot.nix
    ./systemd.nix
    ./system.nix
    ./specialisation.nix
  ];
}
