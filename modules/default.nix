{
  imports = [
    ./hardware/default.nix

    ./system/boot.nix
    ./system/cleanup-root.nix
    ./system/default.nix
    ./system/environment.nix
    ./system/fonts.nix
    ./system/gcp-builder.nix
    ./system/journald.nix
    ./system/networking.nix
    ./system/nix.nix
    ./system/nixpkgs.nix
    ./system/preservation.nix
    ./system/streaming-mode.nix
    ./system/sysctl.nix
    ./system/systemd.nix
    ./system/time.nix
    ./system/xdg.nix
    ./system/zram.nix

    ./programs/default.nix
    ./programs/pass-sops.nix
    ./services/default.nix
    ./services/smartd.nix
    ./security/default.nix
    ./users/default.nix
    ./stylix/default.nix
    ./chaotic.nix
    ./lix.nix
  ];
}
