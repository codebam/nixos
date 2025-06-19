{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      dig
      distrobox
      git
      gparted
      libnotify
      mangohud
      neovim
      nix-output-monitor
      nushell
      podman-compose
      rclone
      run0-sudo-shim
      uutils-coreutils-noprefix
      uutils-findutils
      via
      virt-manager
      wl-clipboard
      xdg-utils
      (inputs.agenix.packages.${pkgs.system}.default.override {
        ageBin = "${pkgs.rage}/bin/rage";
      })
    ];
  };
}
