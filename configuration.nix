{ pkgs, inputs, lib, ... }:

{
  systemd.services = {
    systemd-remount-fs = {
      enable = false;
    };
  };
  boot = {
    initrd.systemd = {
      enable = true;
      services = {
        create-needed-for-boot-dirs = {
          after = [ "unlock-bcachefs--.service" "cleanup-root.service" ];
          serviceConfig.KeyringMode = "inherit";
        };
        cleanup-root = {
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          serviceConfig.KeyringMode = "inherit";
          requiredBy = [ "initrd.target" ];
          after = [
            "unlock-bcachefs--.service"
            "local-fs-pre.target"
          ];
          before = [ "sysroot.mount" ];
          script = ''
            mkdir -p /bcachefs_tmp
            mount -t bcachefs UUID=2ef09b4b-9fb1-4815-8dd2-4aede2ae9add /bcachefs_tmp
            if [[ -e /bcachefs_tmp/@root ]]; then
                mkdir -p /bcachefs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /bcachefs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
                mv /bcachefs_tmp/@root "/bcachefs_tmp/old_roots/$timestamp"
            fi

            delete_subvolume_recursively() {
                IFS=$'\n'
                for i in $(bcachefs subvolume list -o "$1" | cut -f 2- -d ' '); do
                    delete_subvolume_recursively "/bcachefs_tmp/$i"
                done
                bcachefs subvolume delete "$1"
            }

            for i in $(find /bcachefs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
                delete_subvolume_recursively "$i"
            done

            bcachefs subvolume create /bcachefs_tmp/@root
            umount /bcachefs_tmp
          '';
        };
      };
    };
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };

    kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 0;
    };

    supportedFilesystems = [ "bcachefs" ];
    extraModulePackages = [ ];
  };

  stylix = {
    enable = true;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "Fira Code NerdFont";
      };
      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    wireless.iwd = {
      enable = true;
    };
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
      ];
      checkReversePath = false;
      trustedInterfaces = [ "virbr0" ];
    };
  };

  time.timeZone = "America/Toronto";

  systemd = {
    user = {
      extraConfig = ''
        DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      '';
      services.polkit-gnome-authentication-agent-1 = {
        description = "polkit-gnome-authentication-agent-1";
        wantedBy = [ "sway-session.target" ];
        wants = [ "sway-session.target" ];
        after = [ "sway-session.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
      };
    };
  };

  # age = {
  #   identityPaths = [ ./secrets/identities/yubikey-5c.txt ./secrets/identities/yubikey-5c-nfc.txt ];
  #   secrets.hashedpassword.file = ./secrets/hashedpassword.age;
  #   ageBin = "PATH=$PATH:${lib.makeBinPath [pkgs.age-plugin-yubikey]} ${pkgs.rage}/bin/rage";
  # };

  services = {
    ratbagd.enable = true;
    resolved.enable = true;
    speechd.enable = true;
    udev = {
      packages = [ pkgs.via ];
      extraRules = ''
        KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
      '';
    };
    scx = {
      enable = true;
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
      configPackages = [
        (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-high-sample-rate.conf" ''
          context.properties = {
            default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 384000 768000 ]
            default.clock.rate = 384000
          }
        '')
      ];
    };
    flatpak.enable = true;
    udisks2.enable = true;
    gnome.gnome-keyring.enable = true;
    pcscd.enable = true;
  };

  users.mutableUsers = false;
  users.users.codebam = {
    isNormalUser = true;
    home = "/home/codebam";
    description = "Sean Behan";
    extraGroups = [
      "wheel"
      "networkmanager"
      "libvirtd"
      "video"
      "uinput"
    ];
    hashedPassword = "$6$TIP8YR83obmkq8T2$T3lYdPbPj9wysMznNlS5J0qHo2eyTr43aF/ZWSMWHdNRob4dkBB0s3KpBLUgYRTyPZxbb1ZgeqCrrx.DEEkQX1";
    packages = with pkgs; [ flatpak ];
  };

  environment.systemPackages = with pkgs; [
    discord-rpc
    distrobox
    efm-langserver
    git
    gparted
    libnotify
    linux-wallpaperengine
    mangohud
    nil
    nix-output-monitor
    nixpkgs-fmt
    rclone
    steamtinkerlaunch
    virt-manager
    wl-clipboard
    xdg-utils
    via
    (inputs.agenix.packages.${pkgs.system}.default.override { ageBin = "${pkgs.rage}/bin/rage"; })
  ];

  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      fira-code
      fira-code-symbols
      font-awesome
      miracode
      monocraft
      nerd-fonts.fira-code
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "gtk";
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };
  };

  programs = {
    sway.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    dconf.enable = true;
    nix-ld.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    uinput.enable = true;
    graphics = {
      enable = true;
    };
    keyboard.qmk.enable = true;
  };

  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [
            (pkgs.OVMF.override {
              secureBoot = true;
              tpmSupport = true;
            }).fd
          ];
        };
      };
    };
    containers = {
      enable = true;
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  security = {
    polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
            if (subject.user == "codebam") {
                return polkit.Result.YES;
            }
        });
      '';
    };
    pam.services.swaylock = { };
    pam.services.systemd-run0 = { };
    rtkit.enable = true;
    sudo.enable = false;
  };

  zramSwap.enable = true;

  nixpkgs.overlays = [
    (final: prev: {
      # kdePackages = inputs.plasma-beta.legacyPackages.${pkgs.system}.kdePackages;
    })
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
      "open-webui"
    ];


  system.stateVersion = "23.11";
}
