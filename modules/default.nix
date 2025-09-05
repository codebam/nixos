{
  imports = [
    ./hardware/default.nix

    ./system/boot.nix
    ./system/default.nix
    ./system/environment.nix
    ./system/fonts.nix
    ./system/networking.nix
    ./system/nix.nix
    ./system/nixpkgs.nix
    ./system/preservation.nix
    ./system/systemd.nix
    ./system/time.nix
    ./system/virtualisation.nix
    ./system/xdg.nix
    ./system/zram.nix
    ./system/qt.nix

    ./programs/default.nix
    ./services/default.nix
    ./security/default.nix
    ./users/default.nix
    ./stylix/default.nix
  ];
}
