{ pkgs, ... }:
{
  services = {
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos_git;
    };
    scx = {
      enable = true;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
    };
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
          DNSOverTLS = "true";
        };
      };
    };
    speechd.enable = true;
    udev = {
      packages = with pkgs; [
        via
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
      openFirewall = true;
    };
    # Scanner mitigation for the internet-exposed sshd (port 22 is
    # port-forwarded from the router). Password auth is off and root login is
    # denied, so these probes can never succeed -- they only cost journal
    # space. The default sshd jail catches "Invalid user" lines; the
    # sshd-scan jail below catches "Connection closed by ... [preauth]",
    # which is all our scanners emit (with password auth off, sshd never
    # logs "Failed password" for the default filter to trip on). Bans use
    # nftables-multiport because networking.nftables is enabled.
    fail2ban = {
      enable = true;
      jails."sshd-scan" = {
        settings = {
          # sshd logs every preauth close under this unit.
          journalmatch = "_SYSTEMD_UNIT=sshd.service";
          # Longer than the 10m default: nothing legitimate ever ends in
          # a preauth close, so there is no false-positive risk to pay for.
          bantime = "1h";
        };
        filter = {
          # Same structure as the shipped sshd.conf: the F-MLFID wrapper in
          # the prefregex is what satisfies fail2ban 1.1's failure-id check.
          INCLUDES.before = "common.conf";
          Definition = {
            prefregex = "^<F-MLFID>%(__prefix_line)s</F-MLFID><F-CONTENT>.+</F-CONTENT>$";
            failregex = "^Connection closed by (?:authenticating user \\S+ |invalid user \\S+ )?<HOST> port \\d+ \\[preauth\\]$";
          };
        };
      };
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
