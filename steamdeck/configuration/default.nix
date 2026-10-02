_:

{
  imports = [
    ../hardware-configuration.nix
    ./nix.nix
    ./services.nix
    ./boot.nix
    ./environment.nix
    ./viewport.nix
    ./networking.nix
    ./jovian.nix
    ./programs.nix
    ./system.nix
    ./preservation.nix
  ];
}
