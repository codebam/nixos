{
  imports = [
    ../hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./cockpit.nix
    ./environment.nix
    ./flaresolverr.nix
    ./hardware.nix
    ./cloudflare-ddns.nix
    ./litellm.nix
    # ./llm-proxy.nix
    ./networking.nix
    ./nix-serve.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./searx.nix
    ./programs.nix
    ./services.nix
    ./system.nix
    ./systemd.nix
    ./users.nix
  ];
}
