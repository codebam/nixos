{ pkgs, inputs, ... }:

{
  disabledModules = ["virtualisation/libvirtd.nix" ];
  imports = [ ./libvirtd.nix ];
  boot = {
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
    extraModulePackages = [];
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
      options = "--delete-older-than 7d";
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
        22
        80
        443
        11434
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

  services = {
    resolved.enable = true;
    speechd.enable = true;
    udev.extraRules = ''
      KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
    '';
    scx = {
      enable = true;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
      # scheduler = "scx_bpfland";
    };
    kanata = {
      enable = false;
      keyboards = {
        "keyboard".config = ''
          (defsrc
            grv  1    2    3    4    5    6    7    8    9    0    -    =    bspc
            tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
            caps a    s    d    f    g    h    j    k    l    ;    '    ret
            lsft z    x    c    v    b    n    m    ,    .    /    rsft
            lctl lmet lalt           spc            ralt rmet rctl
          )
          (deflayer qwerty
            grv 1    2    3    4    5    6    7    8    9    0    -    @=    bspc
            tab  q    w    e    r    t    y    u    i    o    p    [    ]    \
            caps a    s    d    f    g    h    j    k    l    ;    '    ret
            lsft z    x    c    v    b    n    m    ,    .    /    rsft
            lctl lmet lalt           spc            ralt rmet rctl
          )
          (deflayer layers
            _    @qwr lrld _    _    _    _    _    _    _    _    _    _    _
            @dms @dr0 @dp0 _    _    _    _    _    _    _    _    _    _    _
            _    _    _    _    _    _    _    _    _    _    _    _    _
            _    _    _    _    _    _    _    _    _    _    _    _
            _    _    _              _              _    _    _
          )
          (defalias
            = (tap-hold 200 200 = (layer-toggle layers))
            qwr (layer-switch qwerty)
            dr0 (dynamic-macro-record 0)
            dp0 (dynamic-macro-play 0)
            dms dynamic-macro-record-stop
          )
        '';
      };
    };
    displayManager = {
      sessionPackages = [
        (pkgs.stdenv.mkDerivation rec {
          pname = "flatpak-steam-session";
          version = "1.0";
          buildInputs = [
            pkgs.flatpak
            pkgs.gamescope
          ];

          passthru.providedSessions = [ "flatpak-steam" ];

          src = pkgs.runCommand "flatpak-steam-session-source" { } ''
            mkdir -p $out
            echo "[Desktop Entry]
            Name=Flatpak Steam (Gamescope)
            Comment=Run Steam using Flatpak under Gamescope
            Exec=${pkgs.gamescope}/bin/gamescope -- flatpak run com.valvesoftware.Steam
            Type=Application" > $out/flatpak-steam.desktop
          '';

          installPhase = ''
            mkdir -p $out/share/wayland-sessions
            cp ${src}/flatpak-steam.desktop $out/share/wayland-sessions/flatpak-steam.desktop
          '';
        })
      ];
      sddm = {
        enable = true;
        wayland.enable = true;
      };
    };
    desktopManager.plasma6.enable = true;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
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
    distrobox
    efm-langserver
    git
    libnotify
    nil
    nixpkgs-fmt
    virt-manager
    wl-clipboard
    xdg-utils
    discord-rpc
    mangohud
    steamtinkerlaunch
    vscodium
    rclone
    gparted
    nix-output-monitor
    linux-wallpaperengine
  ];

  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      noto-fonts-cjk-sans
      fira-code
      fira-code-symbols
      font-awesome
      nerd-fonts.fira-code
      monocraft
      miracode
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
      extraPackages = [ pkgs.gamescope-wsi ];
    };
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
      libvirt = inputs.libvirt.legacyPackages.${pkgs.system}.libvirt;
      scx = inputs.scx.legacyPackages.${pkgs.system}.scx;
      xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
        version = "hdr";
        src = prev.fetchFromGitHub {
          owner = "codebam";
          repo = "xdg-desktop-portal-wlr";
          rev = "image-copy-capture";
          hash = "sha256-XjXs627itBLJC2dcA6Pi9t4JwdEFULpgRnXnTbayHb0=";
        };
      });
      wlroots = prev.wlroots.overrideAttrs (old: {
        version = "hdr";
        src = prev.fetchFromGitHub {
          owner = "codebam";
          repo = "wlroots";
          rev = "hdr-04-04";
          hash = "sha256-rlRETNIOzrWDzjd60nWnP+WqBalmvRSGqJAUQqboxFU=";
        };
      });
      sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
        version = "hdr";
        src = prev.fetchFromGitHub {
          owner = "codebam";
          repo = "sway";
          rev = "hdr-04-01";
          hash = "sha256-idsf0YxFjLu0caSdV9lbq3IxQ44DABxwCIRkthbOCO4=";
        };
        buildInputs = (old.buildInputs or []) ++ [ final.wlroots ];
      });
    })
  ];

  system.stateVersion = "23.11";
}
