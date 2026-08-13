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
    ./nix-serve.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./security-triage.nix
    ./searx.nix
    ./programs.nix
    ./services.nix
    ./specialisation.nix
    ./system.nix
    ./systemd.nix
    ./users.nix
  ];
}
