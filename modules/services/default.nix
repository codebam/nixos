{ pkgs, ... }:
{
  services = {
    scx = {
      enable = true;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
    };
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
    tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };
    networkd-dispatcher = {
      enable = true;
      rules."50-tailscale" = {
        onState = [ "routable" ];
        script = ''
          NETDEV=$(ip -o route get 8.8.8.8 | cut -d ' ' -f 5)
          ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
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

        # MelGeek Hive Device
        # Use 'uaccess' to allow the currently logged-in user to access the device
        # without making it world-writable (0666).
        SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
        SUBSYSTEM=="usb_device", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
      '';
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
