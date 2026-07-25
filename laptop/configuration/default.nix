_:

{
  imports = [
    ../hardware-configuration.nix
    ./networking.nix
    ./boot.nix
    ./power.nix
    ./systemd.nix
    ./system.nix
    ./specialisation.nix
  ];
}
