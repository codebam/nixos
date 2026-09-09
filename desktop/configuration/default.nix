{
  imports = [
    ../hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./environment.nix
    ./flaresolverr.nix
    ./hardware.nix
    # ./cloudflare-ddns.nix
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
