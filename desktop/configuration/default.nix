_:

{
  # The module itself is modules/services/hermes-agent.nix, imported by every
  # host and now off everywhere: opencode and pi replaced it as the harnesses
  # on this machine. Flipping this back restores the service, its user, and the
  # hermes-env secret ownership in ./sops.nix.
  hermesAgent.enable = false;

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
