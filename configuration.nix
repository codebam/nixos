{
  pkgs,
  inputs,
  lib,
  ...
}:

{
  boot = {
    plymouth = {
      enable = true;
    };
    initrd.systemd = {
      enable = true;
    };
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        configurationLimit = 10;
      };
      timeout = 0;
      efi.canTouchEfiVariables = true;
    };

    kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 0;
    };

    extraModulePackages = [ ];
  };

  system = {
    switch = {
      enableNg = true;
    };
  };

  stylix = {
    enable = true;
    polarity = "dark";
    targets = {
      console.enable = false;
      plymouth.enable = false;
    };
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
      trusted-users = [
        "root"
        "codebam"
      ];
      system-features = [
        "i686-linux"
        "big-parallel"
      ];
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
    nftables = {
      enable = true;
    };
    firewall = rec {
      enable = true;
      allowedTCPPorts = [
        80
        443
        3389
        5353
        27037
      ];
      allowedUDPPorts = allowedTCPPorts;
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = allowedTCPPortRanges;
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
      services = {
        polkit-gnome-authentication-agent-1 = {
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
      "wireshark"
      "pipewire"
    ];
    hashedPassword = "$6$TIP8YR83obmkq8T2$T3lYdPbPj9wysMznNlS5J0qHo2eyTr43aF/ZWSMWHdNRob4dkBB0s3KpBLUgYRTyPZxbb1ZgeqCrrx.DEEkQX1";
    packages = [ ];
    shell = pkgs.fish;
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCo4kxTz34eDK4j/Zazo7AjiUKrMQIFL/PFZ21ipqcjAUjcMK72c7/DL2OqKANJAkYsXD39+wFvjvzoHwBRJ3YciWRxulT+I0yIDwoOYWyWgYWAO/f2pUcPVjcwj4LQ6aoVeINkTqKYrXVbw9t8pJ8R34X7J46kgKW/G4rPKlC7ipAbS0O0dXt95p5SgKx5i4Cn5H/EAumuL3FxweSviPYW53FmXEtaZzkoUbAbBrh6vnWopNZVqBy7ZhS11ca3KVPNv3EEZ6mLQYsvIGhn163S5YLdJfDCXHJ+umFUAO1kqLxSeUqYHyJ5Iz29/64oaviM2ECPEros3gYVE2XR5GDhHU7oGqQ8wiho8KQS2nL/tIBi7eP6hwi0Ho5InXM8O0XhDfq+/WRNCJrEzakrtHygqO+DxM06QlOS1g74MHca+1ZGarY7l2+eKkuoddUPoMoGqRlRFrMH77IwXhYv616iUMz3cXLfbEOVlrZ7FDwJvql0k9ZeDzQMnz66chwHUydlY1waqenr6Qu48a2g9JfXSb0zB2fYBBlV+5wX1YCaZ8fHTi5QA5RK0bFT2EPXvuFdTHBppDbG5HVZI4dIZQ/urY2XVc8hZ6v90A0PW/zGYArG5r3kntWb7e58C2cwY/19y0s/aZu01tepZsBLHsK/ZrpTzgrcwaunaP0Sxl+lwQ== cardno:9_082_676" # yubikey-5c
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDCNeFVxzMGKcckiXZBmDkLsB8yE7zmT88V5GgjJpkkEYnyk7lvJb+zRWYbAW0k5j+Tf1iNWIUy5EFCm5wfqq57PwhaR8TlMmClQQaRUDWotmqkYVKRiFjFIklUMAcmWVjhxqWtJdo8iBX7+S2i74z4ivku6xI+ifQ8Xr5OoNONYJvVa/nfakCWjFLQ51+RnXNEcEV76v/dfG482uvhqubZgjgfYfuWHSUZC65D6LstTrEa/DtAUc/47unFAMm5U9L4C33m7RKS/JllXW47cT0KJBUywYcc6+euzPdQhAVGj8fUKxjRHWIYcuhTSjrDYVgXwasjnHKOmRxlyClSFTD7 cardno:15_606_805" # yubikey-5c-nfc
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFm8MinRasfhAbMOkQhz+/yXgKBgV1N2J98dlLJ70daz" # servercat
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7yDL3drFmgNAFIaTgoamlGaTBiKdm+eIK8q3JJTpKh codebam@nixos-steamdeck" # nixos-steamdeck
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnwv9Ifx6b82N/oRMCAKYi0vWCDyue9Mkf2Fh8lLidm codebam@nixos-laptop" # nixos-laptop
    ];
  };

  environment.systemPackages = with pkgs; [
    run0-sudo-shim
    nushell
    uutils-coreutils-noprefix
    uutils-findutils
    distrobox
    efm-langserver
    git
    gparted
    libnotify
    mangohud
    nil
    nix-output-monitor
    nixpkgs-fmt
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
    fish = {
      enable = true;
    };
    nix-ld.enable = true;
    wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    kdeconnect.enable = true;
    sway.enable = true;
    dconf.enable = true;
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
    acme = {
      acceptTerms = true;
      defaults = {
        email = "codebam@riseup.net";
      };
    };
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
    pam = {
      services = {
        swaylock = { };
        systemd-run0 = { };
      };
    };
    rtkit.enable = true;
    sudo.enable = false;
  };

  zramSwap.enable = true;

  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      commonMountOptions = [
        "x-gvfs-hide"
      ];
      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
          how = "symlink";
        }
      ];
      directories = [
        {
          directory = "/etc/nixos";
          user = "codebam";
          group = "users";
        }
        "/var/lib/sbctl"
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/OpenRGB"
        "/var/lib/systemd/coredump"
        "/etc/NetworkManager/system-connections"
        "/var/lib/iwd"
        "/etc/ssh"
        {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
          mode = "0700";
        }
        {
          directory = "/var/lib/private/ollama";
          user = "nobody";
          group = "nogroup";
        }
        {
          directory = "/var/lib/private/open-webui";
          user = "nobody";
          group = "nogroup";
        }
        {
          directory = "/var/lib/acme";
          user = "acme";
          group = "nginx";
        }
      ];
      users = {
        root = {
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
          ];
        };
        codebam = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
            {
              directory = ".gnupg";
              mode = "0700";
            }
            {
              directory = ".nixops";
              mode = "0700";
            }
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
            "Downloads"
            "Music"
            "Pictures"
            "Documents"
            "Videos"
            "Games"
            ".local/share/direnv"
            ".local/share/fish"
            ".steam"
            ".local/share/Steam"
            ".librewolf"
            ".password-store"
            ".local/state/wireplumber"
            ".config/Element"
            ".config/discord"
            ".local/share/TelegramDesktop"
            ".local/share/zoxide"
            ".config/YouTube Music"
            ".local/share/PrismLauncher"
            ".config/OpenRGB"
            ".config/heroic"
            ".config/nushell"
            ".cache/nix-index"
          ];
        };
      };
    };
  };

  systemd.tmpfiles.settings.preservation = {
    "/home/codebam/.config".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local/share".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local/state".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.cache".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
  };

  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };

  nixpkgs = {
    config = {
      checkMeta = true;
      showDerivationWarnings = [ "maintainerless" ];
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "steam"
          "steam-original"
          "steam-run"
          "steam-unwrapped"
          "open-webui"
          "discord"
          "steamdeck-hw-theme"
          "steam-jupiter-unwrapped"
          "libretro-genesis-plus-gx"
          "libretro-snes9x"
          "libretro-fbneo"
          "vscode"
        ];
    };
    overlays = [
      (final: prev: {
      })
    ];
  };
}
