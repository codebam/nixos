{ pkgs, ... }:
{
  services = {
    tailscale = {
      enable = true;
      openFirewall = true;
    };
    ratbagd.enable = true;
    resolved.enable = true;
    speechd.enable = true;
    udev = {
      packages = with pkgs; [
        via
        yubikey-personalization
      ];
      extraRules = ''
        KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
      '';
    };
    scx = {
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
    };
    desktopManager.plasma6.enable = true;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
      openFirewall = true;
    };
    fwupd.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    udisks2.enable = true;
    gnome.gnome-keyring.enable = true;
    pcscd.enable = true;
  };
}
