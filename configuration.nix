{ pkgs, inputs, lib, ... }:

{
  # systemd.package = inputs.staging-next.legacyPackages.${pkgs.system}.systemd;
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
      };
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 10;
    };
    kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = let
    #   linux_custom_pkg = { buildLinux, ... } @ args:
    #     buildLinux (args // rec {
    #       version = "6.12";
    #       modDirVersion = version;
    #       src = inputs.linux-custom;
    #       kernelPatches = [];
    #     } // (args.argsOverride or {}));
    #   linux_custom = pkgs.callPackage linux_custom_pkg{};
    # in
    #   pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_custom);

    supportedFilesystems = [ "bcachefs" ];
    extraModulePackages = [ ];
  };
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
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
      allowedTCPPorts = [ 22 8211 25565 ];
      checkReversePath = false;
      trustedInterfaces = [ "virbr0" ];
    };
    # wireguard = {
    #   interfaces = {
    #     wg0 = {
    #       ips = [
    #         "10.128.251.130/32"
    #         "fc00:bbbb:bbbb:bb01:d::fb82/128"
    #       ];
    #       privateKey = "ANbBaaTEjylLrs8FJ2ynPvVOoNt0+8+eRZcH9OVPCn0=";
    #       peers = [
    #         {
    #           publicKey = "uhbuY1A7g0yNu0lRhLTi020kYeAx34ED30BA5DQRHFo=";
    #           allowedIPs = [
    #             "0.0.0.0/0"
    #             "::/0"
    #           ];
    #           endpoint = "178.249.214.2:3431";
    #           persistentKeepalive = 25;
    #         }
    #       ];
    #     };
    #   };
    # };
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

    # tmpfiles.rules = [
    #   "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    # ];
  };

  services = {
    kanata = {
      enable = true;
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
  grv 1    2    3    4    5    6    7    8    9    0    -    =    bspc
  tab  q    w    e    r    t    y    u    i    o    p    [    ]    @\
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
  \ (tap-hold 200 200 \ (layer-toggle layers))
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
          buildInputs = [ pkgs.flatpak pkgs.gamescope ];

          passthru.providedSessions = ["flatpak-steam"];

          src = pkgs.runCommand "flatpak-steam-session-source" { } ''
            mkdir -p $out
            echo "[Desktop Entry]
            Name=Flatpak Steam (Gamescope)
            Comment=Run Steam using Flatpak under Gamescope
            Exec=${pkgs.gamescope}/bin/gamescope -- flatpak run com.valvesoftware.Steam
            Type=Application" > $out/flatpak-steam.desktop
          '';

          # Install phase writes the session file directly
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
    avahi.enable = true;
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
  # users.users.root = {
  #   password = null;
  # };
  users.users.codebam = {
    isNormalUser = true;
    home = "/home/codebam";
    description = "Sean Behan";
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "video" "uinput" ];
    hashedPassword = "$6$TIP8YR83obmkq8T2$T3lYdPbPj9wysMznNlS5J0qHo2eyTr43aF/ZWSMWHdNRob4dkBB0s3KpBLUgYRTyPZxbb1ZgeqCrrx.DEEkQX1";
    packages = with pkgs; [
      flatpak
    ];
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
    # inputs.firefox-nightly.packages.${pkgs.system}.firefox-nightly-bin
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
    ];
  };

  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "gtk";
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };
  };

  programs = {
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
      settings = {
        LE = {
          MinConnectionInterval = 7;
          MaxConnectionInterval = 9;
          ConnectionLatency = 0;
        };
      };
    };
    uinput.enable = true;
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
    polkit.enable = true;
    pam.services.swaylock = { };
    pam.services.systemd-run0 = { };
    rtkit.enable = true;
    sudo.enable = false;
  };

  zramSwap.enable = true;

  hardware = {
    graphics = {
      enable = true;
      extraPackages = [ pkgs.gamescope-wsi ];
    };
  };

  nixpkgs.overlays = [
    (final: prev: {
      # mesa = inputs.mesa-25.legacyPackages.${pkgs.system}.mesa;
      # flatpak = inputs.flatpak-stable.legacyPackages.${pkgs.system}.flatpak;
      # mesa = prev.mesa.overrideAttrs (old: {
      #   src = prev.fetchFromGitLab {
      #     domain = "gitlab.freedesktop.org";
      #     owner = "mesa";
      #     repo = "mesa";
      #     rev = "0d29ddb328da76db391640a4186ee5a0bf078076";
      #     hash = "sha256-xvhwTZWyj34eL34G6geHFmWMqr+PpRQoKcKi+qnTEXc=";
      #   };
      #   patches = [];
      #   mesonFlags = lib.filter (flag: !(lib.isString flag && (builtins.match ".*clang-libdir.*" flag != null || builtins.match ".*opencl-spirv.*" flag != null))) old.mesonFlags;
      # });
      # sway = prev.sway.overrideAttrs (old: {
      #   src = prev.fetchFromGitHub {
      #     owner = "codebam";
      #     repo = "sway";
      #     rev = "8acb0482da68af69d52ab168f9e30e2464b9c7a3";
      #     hash = "sha256-7WOgud8xXrSgoGnWL2Fmk+RfROaY8LcAo7pkeAqHFwA=";
      #   };
      # });
    })
  ];

  system = {
    stateVersion = "23.11";
  };
}
