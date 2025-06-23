{ config
, pkgs
, lib
, inputs
, ...
}:
{
  disabledModules = [ "services/networking/searx.nix" ];
  imports = [
    ./boot.nix
    ./environment.nix
    ./fonts.nix
    ./hardware.nix
    ./networking.nix
    ./nix.nix
    ./nixpkgs.nix
    ./preservation.nix
    ./programs.nix
    ./security.nix
    ./services.nix
    ./stylix.nix
    ./systemd.nix
    ./system.nix
    ./time.nix
    ./users.nix
    ./virtualisation.nix
    ./xdg.nix
    ./zram.nix
    ../custom-modules/searx.nix
  ];
}
