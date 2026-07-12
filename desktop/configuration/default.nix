_:

{
  imports = [
    ../hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./environment.nix
    ./hardware.nix
    ./jovian.nix
    ./networking.nix
    ./nix.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./programs.nix
    ./services.nix
    ./specialisation.nix
    ./system.nix
    ./systemd.nix
    ./users.nix
    ./virtualisation.nix
    ./zram.nix
  ];
}
