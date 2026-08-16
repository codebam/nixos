_:

{
  # Both hosts run OBS (desktop-laptop/home.nix). The module is inert until
  # `streaming-mode on`; buildCpus is left at null here because the two have
  # different core counts -- the desktop sets its own reservation in
  # desktop/configuration/systemd.nix.
  streamingMode.enable = true;

  imports = [
    ./virtualisation.nix
    ./environment.nix
    ./programs.nix
    ./services.nix
    ./systemd.nix
  ];
}
