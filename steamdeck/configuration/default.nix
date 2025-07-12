_:

{
  imports = [
    ../hardware-configuration.nix
    ./nix.nix
    ./services.nix
    ./boot.nix
    ./environment.nix
    ./networking.nix
    ./jovian.nix
    ./programs.nix
    ./nixpkgs.nix
    ./system.nix
    ./preservation.nix
    ./specialisation.nix
  ];
}
