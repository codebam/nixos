_:

{
  imports = [
    ./gcp-nix-builder.nix
    ./virtualisation.nix
    ./environment.nix
    ./services.nix
    ./systemd.nix
  ];
}
