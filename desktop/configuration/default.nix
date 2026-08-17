_:

{
  # The module itself is modules/services/hermes-agent.nix, imported by every
  # host and off everywhere but here.
  hermesAgent.enable = true;

  imports = [
    ../hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./cockpit.nix
    ./environment.nix
    ./flaresolverr.nix
    ./hardware.nix
    ./networking.nix
    ./nix-serve.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./searx.nix
    ./programs.nix
    ./services.nix
    ./specialisation.nix
    ./system.nix
    ./systemd.nix
    ./users.nix
  ];
}
