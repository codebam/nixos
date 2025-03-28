{ pkgs, lib, ... }:

{
  # imports = [ ./libvirtd.nix ];
  # disabledModules = [ "virtualisation/libvirtd.nix" ];
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
      };
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 10;
    };

    kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 0;
    };

    supportedFilesystems = [ "bcachefs" ];
    extraModulePackages = [ ];
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

    # tmpfiles.rules = [
    #   "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    # ];
  };

  services = {
    # nixseparatedebuginfod.enable = true;
    speechd.enable = true;
    udev.extraRules = ''
      KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
    '';
    scx = {
      enable = true;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
    };
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
    # mpv
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
      # settings = {
      #   LE = {
      #     MinConnectionInterval = 7;
      #     MaxConnectionInterval = 9;
      #     ConnectionLatency = 0;
      #   };
      # };
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

  hardware = {
    graphics = {
      enable = true;
      extraPackages = [ pkgs.gamescope-wsi ];
    };
  };

  nixpkgs.overlays = [
    (final: prev: {
      # libvirt = prev.libvirt.overrideAttrs {
      #   postInstall =
      #     lib.replaceStrings [ "rm $out/lib/systemd/system/{virtlockd,virtlogd}.*\n" ] [ "" ]
      #       prev.libvirt.postInstall;
      # };
      wlroots = prev.wlroots.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "codebam";
          repo = "wlroots";
          rev = "hdr-new";
          hash = "sha256-e3WSawnJMgs7Ilj+TgD2nTer8VdedXIYuEjV91yORi0=";
        };
      });
      sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "codebam";
          repo = "sway";
          rev = "hdr-new";
          hash = "sha256-BeuTGF99wS7McRYLcYnm9GVYpfree1cEs6l8SmV4vgA=";
        };
        buildInputs = (old.buildInputs or []) ++ [ final.wlroots ];
      });
      # mpv-unwrapped = prev.mpv-unwrapped.overrideAttrs (old: {
      #   src = prev.fetchFromGitHub {
      #     owner = "mpv-player";
      #     repo = "mpv";
      #     rev = "a8f5beb5a38e0ed169a9fb9faff6c5ca0a43dfee";
      #     hash = "sha256-HhzfbIwaVQMH8KTPNL5UPVsp8xfXm9pljL7lxUF4J0Q=";
      #   };
      #   postPatch = lib.concatStringsSep "\n" [
      # # Don't reference compile time dependencies or create a build outputs cycle
      # # between out and dev
      # ''
      # substituteInPlace meson.build \
      #   --replace-fail "conf_data.set_quoted('CONFIGURATION', meson.build_options())" \
      #                  "conf_data.set_quoted('CONFIGURATION', '<omitted>')"
      # ''
      # # A trick to patchShebang everything except mpv_identify.sh
      # ''
      # pushd TOOLS
      # mv mpv_identify.sh mpv_identify
      # patchShebangs *.py *.sh
      # mv mpv_identify mpv_identify.sh
      # popd
      # ''
      # ];
      # });
    })
  ];

  system = {
    stateVersion = "23.11";
  };
}
