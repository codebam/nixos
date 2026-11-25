{ pkgs, lib, ... }:
{
  imports = [ ./smartd.nix ];

  services = {
    # Off: sched-ext stays opt-in -- desktop turns it on with mkForce in
    # desktop/configuration/services.nix, the other hosts stay on EEVDF.
    # The desktop's default was scx_lavd until 1.1.3 regressed on kernel 7.2
    # (a migration-disabled, single-CPU-affine task was never dispatched and
    # waited out the 21s RCU stall timeout; fixed upstream in 6d31ddd8973 and
    # shipped in 1.1.4). It then ran scx_cake, which is game-tuned.
    #
    # It now defaults to scx_eevdf, the faithful port of the kernel's own
    # EEVDF: fair share is not a policy it can get wrong, so no task is owed
    # service on a special path that can be missed, and it is the scheduler
    # least likely to strand a thread mid-compile. Cake is still built and
    # installed; `scx-switch game` moves to it, `scx-switch` (or
    # `scx-switch work`) moves back.
    #
    # nixpkgs 26.11 removed services.scx in favour of the scx-loader daemon
    # (services.scx-loader); default_sched replaces the old `scheduler`.
    # Both pins live in modules/system/nixpkgs.nix: scx for the scheduler
    # binaries, scx-loader for the daemon, whose v1.1.3 predates scx_eevdf.
    scx-loader = {
      enable = false;
      config.default_sched = "scx_eevdf"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_eevdf/README.md
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

    tailscale = {
      enable = true;
      # Client-only by default: subnet-router/exit-node ("both") plus
      # an open firewall hole belongs on the desktop alone, which
      # overrides these in desktop/configuration/networking.nix.
      # Leaving "both" on the laptop/Deck needlessly exposes UDP 41641
      # on whatever WAN they sit behind.
      openFirewall = lib.mkDefault false;
      useRoutingFeatures = lib.mkDefault "client";
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
        # uaccess alone grants the seat's active user; an explicit
        # MODE was redundant with the tag's dynamic ACL.
        KERNEL=="ntsync", TAG+="uaccess"

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
