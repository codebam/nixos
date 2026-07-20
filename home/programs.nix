{
  pkgs,
  lib,
  ...
}:

{
  programs = {
    iamb = {
      enable = true;
      settings = {
        default_profile = "unredacted.org";
        profiles = {
          "unredacted.org" = {
            user_id = "@codebam:unredacted.org";
            url = "https://matrix.unredacted.org";
          };
        };
      };
    };
    google-chrome = {
      enable = true;
    };
    chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
    };
    ghostty = {
      enable = true;
      package = pkgs.ghostty_git;
      enableFishIntegration = true;
      settings = {
        cursor-style = "block";
        shell-integration-features = "no-cursor";
        cursor-style-blink = false;
        window-padding-x = 0;
        window-padding-y = 0;
        app-notifications = "no-clipboard-copy";
      };
    };
    helix = {
      enable = true;
      package = pkgs.helix_git;
      defaultEditor = true;
      languages = {
        language = [
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = "${pkgs.nixfmt}/bin/nixfmt";
            };
            language-servers = [ "nixd" ];
          }
        ];
        language-server.nixd = {
          command = "${pkgs.nixd}/bin/nixd";
          config.nixd = {
            nixpkgs.expr = "import (builtins.getFlake \"/etc/nixos\").inputs.nixpkgs { }";
            options.nixos.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.nixos-desktop.options";
          };
        };
      };
      settings = {
        theme = lib.mkForce "rose_pine";
        editor = {
          lsp.display-inlay-hints = true;
          end-of-line-diagnostics = "hint";
          inline-diagnostics.cursor-line = "warning";
          bufferline = "multiple";
        };
        keys = {
          normal = {
            X = "select_line_above";
            x = "select_line_below";
          };
        };
      };
    };
    carapace = {
      enable = true;
      enableNushellIntegration = true;
    };
    nushell = {
      enable = true;
      extraConfig = ''
        let carapace_completer = {|spans|
        carapace $spans.0 nushell ...$spans | from json
        }
        $env.config = {
         show_banner: false,
         completions: {
         case_sensitive: false
         quick: true
         partial: true
         algorithm: "fuzzy"
         external: {
             enable: true 
             max_results: 100 
             completer: $carapace_completer # check 'carapace_completer' 
           }
         }
        } 
        $env.PATH = ($env.PATH | 
        split row (char esep) |
        prepend /home/codebam/.local/bin |
        append /usr/bin/env
        )
        $env.SSH_AUTH_SOCK = (gpgconf --list-dirs agent-ssh-socket)
        $env.GPG_TTY = (tty)
      '';
    };
    i3status-rust = {
      enable = true;
      bars = {
        default = {
          settings = {
            theme = {
              overrides = {
                idle_bg = "#000000";
                idle_fg = "#cdd6f4";
                good_bg = "#000000";
                good_fg = "#a6e3a1";
                warning_bg = "#000000";
                warning_fg = "#f9e2af";
                critical_bg = "#000000";
                critical_fg = "#f38ba8";
                info_bg = "#000000";
                info_fg = "#89b4fa";
                separator_bg = "#000000";
                separator_fg = "#45475a";
                separator = "";
                alternating_tint_bg = "#000000";
              };
            };
          };
          icons = "awesome6";
        };
      };
    };
    firefox = {
      enable = true;
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DontCheckDefaultBrowser = true;
        DisablePocket = true;
        SearchBar = "unified";
        ExtensionSettings = {
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "force_installed";
          };
        };
      };
      profiles.default = {
        id = 0;
        name = "default";
        isDefault = true;
        path = "ry5m9sd1.default";
        settings = {
          "sidebar.verticalTabs" = true;
          "sidebar.revamp" = true;
          # Need this for discord
          "media.peerconnection.enabled" = true;
          # Enable strict tracking protection
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = true;
          "privacy.trackingprotection.fingerprinting.enabled" = true;
          "privacy.trackingprotection.cryptomining.enabled" = true;
          # Resist fingerprinting (Tor/LibreWolf style)
          "privacy.resistFingerprinting" = true;
          # This is too annoying to use
          "privacy.resistFingerprinting.letterboxing" = false;
          "privacy.resistFingerprinting.exemptedDomains" =
            "app.element.io,element.io,discord.com,canary.discord.com";
          # First-party isolation to prevent cross-site correlation
          "privacy.firstparty.isolate" = false;
          # Disable APIs commonly used for fingerprinting
          "webgl.disabled" = true;
          "dom.webaudio.enabled" = true;
          "media.navigator.enabled" = true;
          "dom.netinfo.enabled" = false;
          "media.video_stats.enabled" = true;
          "dom.gamepad.enabled" = false;
          "device.sensors.enabled" = false;
          "geo.enabled" = false;
          # General tracking prevention
          "privacy.query_stripping.enabled" = true;
          "browser.send_pings" = false;
          # Security & network connections
          "dom.security.https_only_mode" = true;
          "browser.search.suggest.enabled" = false;
          "network.dns.disablePrefetch" = true;
          "network.prefetch-next" = false;
          "network.http.speculative-parallel-limit" = 0;
          "network.predictor.enabled" = false;
        };
      };
    };
    mpv = {
      enable = true;
      config = {
        save-position-on-quit = true;
        resume-playback = true;
      };
    };
    swaylock = {
      enable = true;
    };
    mangohud = {
      enable = true;
      package = pkgs.mangohud_git;
      settings = {
        legacy_layout = false;
        horizontal = true;
        font_size = 20;
        background_alpha = 0.0;
        hud_no_margin = true;
        present_mode = true;
        fps = true;
        frametime = true;
        frame_timing = true;
        histogram = true;
        gpu_stats = true;
        gpu_temp = true;
        gpu_load_change = true;
        gpu_power = true;
        gpu_mhz = true;
        vram = true;
        cpu_stats = true;
        cpu_temp = true;
        cpu_load_change = true;
        cpu_mhz = true;
        cpu_power = true;
        ram = true;
        vulkan_driver = true;
        engine_version = true;
        display_server = true;
      };
    };
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
        set -gx PATH $PATH /home/codebam/.cargo/bin
        set -gx SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
        set -gx SEARXNG_API_URL http://localhost:8081
        set -gx EDITOR hx
        set -gx NIXOS_OZONE_WL 1
        # set -gx OBS_VKCAPTURE 1
        set -gx WLR_RENDERER vulkan
        # set -gx AMD_USERQ 1
        # set -gx RADV_PERFTEST userq
        set -gx GTK_USE_PORTAL 1
        # set -gx WLR_DRM_NO_ATOMIC 1
        # set -gx MANGOHUD_CONFIGFILE /home/codebam/.config/MangoHud/MangoHud.conf
        # set -gx PROTON_ENABLE_WAYLAND 1
        # set -gx PROTON_ENABLE_HDR 1
        # set -gx PROTON_USE_NTSYNC 1
        set _JAVA_AWT_WM_NONREPARENTING 1
        function __hm_play_bell_on_postexec --on-event fish_postexec
          if test $status -eq 0
            tput bel
          else
            ${pkgs.pipewire}/bin/pw-play ${../error.wav}
          end
        end
      '';
    };
    bash = {
      enable = true;
    };
    git = {
      enable = true;
      settings = {
        user = {
          email = "codebam@riseup.net";
          name = "Sean Behan";
        };
        pull = {
          rebase = true;
        };
        push = {
          default = "simple";
          autoSetupRemote = true;
        };
        init = {
          defaultBranch = "main";
        };
        core = {
          editor = "hx";
          autocrlf = "input";
          excludesfile = "~/.gitignore";
        };
        diff = {
          colorMoved = "default";
        };
        branch = {
          autosetupmerge = "always";
          autosetuprebase = "always";
        };
      };
    };
    tmux = {
      enable = true;
      terminal = "tmux-256color";
      prefix = "C-a";
      mouse = true;
      keyMode = "vi";
      clock24 = true;
      extraConfig = ''
        set -ga terminal-overrides ",*256col*:Tc"
        bind-key C-a last-window
        bind-key a send-prefix
        bind-key b set status
        bind s split-window -v
        bind v split-window -h
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
        set -sg escape-time 100
        set-option -g status-interval 5
        set-option -g automatic-rename on
        set-option -g automatic-rename-format '#{b:pane_current_path}'
      '';
      plugins = with pkgs.tmuxPlugins; [
        {
          plugin = resurrect;
          extraConfig = ''
            set -g @resurrect-strategy-vim 'session'
            set -g @resurrect-strategy-nvim 'session'
            set -g @resurrect-capture-pane-contents 'on'
            set -g @resurrect-processes '"~vi->vi -S" "~hx" "~e"'
          '';
        }
      ];
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      defaultOptions = [
        "--height 40%"
        "--layout=reverse"
        "--border"
        "--inline-info"
      ];
      tmux = {
        enableShellIntegration = true;
      };
    };
    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
      settings = {
        add_newline = false;
        git_metrics.disabled = false;
        gcloud.disabled = true;
        scan_timeout = 10;
        status = {
          disabled = false;
          format = "exited with code [$status](bold red) ";
        };
        character = {
          success_symbol = "\\$(bold green)";
          error_symbol = "[\\$](bold red)";
        };
      };
    };
    fd = {
      enable = true;
      hidden = true;
      ignores = [
        ".git/"
        "*.bak"
      ];
    };
    fastfetch = {
      enable = true;
      settings = {
        logo = {
          source = "nixos";
          padding = {
            right = 1;
          };
        };
        modules = [
          "title"
          "separator"
          "os"
          "host"
          "kernel"
          "uptime"
          "packages"
          "shell"
          "display"
          "de"
          "wm"
          "terminal"
          "cpu"
          "gpu"
          "memory"
          "disk"
          "colors"
        ];
      };
    };
    gpg = {
      enable = true;
      scdaemonSettings = {
        disable-ccid = true;
      };
      settings = {
        personal-digest-preferences = "SHA512";
        personal-cipher-preferences = "AES256";
        default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES CAMELLIA256 CAMELLIA192 CAMELLIA128 ZLIB BZIP2 ZIP Uncompressed";
        use-agent = true;
      };
    };
    wlogout = {
      enable = true;
      layout = [
        {
          label = "lock";
          action = "${pkgs.swaylock}/bin/swaylock";
          text = "Lock";
          keybind = "l";
        }
        {
          label = "hibernate";
          action = "systemctl hibernate";
          text = "Hibernate";
          keybind = "h";
        }
        {
          label = "logout";
          action = "${pkgs.sway}/bin/swaymsg exit";
          text = "Exit";
          keybind = "e";
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
        }
        {
          label = "suspend";
          action = "systemctl suspend";
          text = "Suspend";
          keybind = "u";
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
        }
      ];
      style = ''
        * {
          background-image: none;
          transition: 200ms;
        }
        window {
          background-color: rgba(12, 12, 12, 0.85);
        }
        button {
          color: #cdd6f4;
          background-color: rgba(30, 30, 46, 0.5);
          border-style: solid;
          border-width: 2px;
          border-color: #313244;
          border-radius: 20px;
          margin: 10px;
          background-repeat: no-repeat;
          background-position: center;
          background-size: 25%;
        }
        button:focus, button:active, button:hover {
          background-color: rgba(137, 180, 250, 0.2);
          border-color: #89b4fa;
          color: #89b4fa;
        }
        #lock {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/lock.png");
        }
        #logout {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/logout.png");
        }
        #suspend {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/suspend.png");
        }
        #hibernate {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/hibernate.png");
        }
        #shutdown {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/shutdown.png");
        }
        #reboot {
          background-image: url("${pkgs.wlogout}/share/wlogout/icons/reboot.png");
        }
      '';
    };
  };
}
