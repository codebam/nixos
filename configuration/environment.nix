{ pkgs, inputs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      run0-sudo-shim
      nushell
      uutils-coreutils-noprefix
      uutils-findutils
      distrobox
      git
      gparted
      libnotify
      mangohud
      nix-output-monitor
      rclone
      virt-manager
      wl-clipboard
      xdg-utils
      via
      dig
      neovim
      (inputs.agenix.packages.${pkgs.system}.default.override {
        ageBin = "${pkgs.rage}/bin/rage";
      })
    ];
  };
}
