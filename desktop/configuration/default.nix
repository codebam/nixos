_:

{
  imports = [
    ../hardware-configuration.nix
    ./hermes-agent.nix
    ./sops.nix
    ./boot.nix
    ./environment.nix
    ./flaresolverr.nix
    ./hardware.nix
    ./networking.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./security-triage.nix
    ./programs.nix
    ./services.nix
    ./specialisation.nix
    ./system.nix
    ./systemd.nix
    ./users.nix
  ];
}
