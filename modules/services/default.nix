{ pkgs, lib, ... }:
{
  services = {
    # Off: scx_lavd 1.1.3 on kernel 7.2.0 does not dispatch tasks that are
    # migration-disabled and affine to a single CPU onto that CPU, which then
    # sits in idle_sched_class while the task waits out the 21s RCU stall
    # timeout and the kernel ejects the scheduler. 103 ejections in one
    # 3-hour boot, with the machine otherwise near idle (load 3, PSI cpu
    # 1.1%). Firefox took the worst of it, having threads in migrate-disabled
    # BPF hooks -- systemd's restrict_filesystems on openat, sd_fw_egress on
    # sendmsg -- more or less constantly. EEVDF instead until a newer scx.
    scx = {
      enable = false;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
    };
    # Portals are already set up for sway in modules/system/xdg.nix, which is
    # what flatpak apps need to reach files, screenshare, and the theme.
    # /var/lib/flatpak and ~/.local/share/flatpak are preserved across the
    # root wipe in modules/system/preservation.nix.
    #
    # The flathub remote is not declarative -- nothing in nixpkgs adds it --
    # so a fresh machine still needs, once:
    #   flatpak remote-add --if-not-exists flathub \
    #     https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak.enable = true;

    lsfg-vk = {
      enable = pkgs.lib.mkDefault false;
      ui.enable = pkgs.lib.mkDefault false;
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
          NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 2>/dev/null | cut -d ' ' -f 5)
          if [ -n "$NETDEV" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null || true
          fi
        '';
      };
    };
    ratbagd.enable = true;
    resolved = {
      enable = true;
      settings = {
        Resolve = {
          DNS = "1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net";
          FallbackDNS = "8.8.8.8#dns.google";
          DNSSEC = "allow-downgrade";
          # Strict here, opportunistic on the laptop (see
          # laptop/configuration/networking.nix): a portable machine that hits
          # a captive portal with strict DoT has no working DNS at all, and no
          # way to reach the portal page to fix it.
          DNSOverTLS = lib.mkDefault "true";
        };
      };
    };
    # Off: nothing on the desktop or laptop speaks. Enabling it pulls
    # espeak-ng, which pulls mbrola, whose voice data alone is 644 MB. Turn
    # back on with a screen reader, not before.
    #
    # mkForce, and it has to be: two nixos modules set this to a plain `true`
    # rather than mkDefault, so an ordinary false is an eval error rather than
    # an override. graphical-desktop.nix turns it on for any graphical session
    # (desktop and laptop), and orca.nix does the same on the Steam Deck, which
    # pulls that module in via Jovian's SteamOS session.
    #
    # What this costs: orca, if it is ever launched on any of these hosts, will
    # be mute. Nothing enables it -- the Deck's only a11y setting is
    # screen-keyboard-enabled -- so that is a hypothetical, but it is the thing
    # to undo first if a screen reader is ever wanted.
    speechd.enable = lib.mkForce false;
    udev = {
      packages = with pkgs; [
        yubikey-personalization
      ];
      extraRules = ''
        KERNEL=="ntsync", MODE="0660", TAG+="uaccess"

        # MelGeek Made68 Ultra
        SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
        SUBSYSTEM=="usb_device", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
      '';
    };
    openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/persistent/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
        {
          path = "/persistent/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
        # Off, or sshd still offers keyboard-interactive and every scanner
        # gets to walk the PAM stack. It cannot succeed here — password auth
        # is off and root login is denied — but it costs a PAM round trip per
        # attempt and fills the journal with "PAM: Authentication failure for
        # root" (~1700 lines/day from one netblock before this).
        KbdInteractiveAuthentication = false;
      };
      # Deliberately false: sshd is reachable over the tailnet only. No port
      # 22 hole is punched in the input chain, so the only path to sshd is
      # tailscale0, which is in networking.firewall.trustedInterfaces
      # (modules/system/networking.nix). Do not set this back to true --
      # openFirewall opens 22 on every interface including the WAN, which is
      # what the router forward and the fail2ban/nftables scanner blocks
      # removed alongside this used to be cleaning up after.
      openFirewall = false;
    };
    fwupd.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      extraConfig.pipewire-pulse = {
        "pulse.properties" = {
          "module.passthrough" = true;
        };
        "context.modules" = [
          {
            name = "libpipewire-module-protocol-pulse";
            args = { };
          }
        ];
      };
    };
    udisks2.enable = true;
    gnome.gnome-keyring.enable = true;
    pcscd.enable = true;
  };
}
