{
  pkgs,
  lib,
  inputs,
  osConfig,
  ...
}:

{
  programs = {
    # Rest of fzf comes from home/shell-common.nix.
    fzf.defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
    ];

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
    # Client for the mopidy MPD socket in home/mopidy.nix, which is Navidrome
    # behind the MPD protocol. Two screens do not work against that backend
    # and neither is worth chasing: the visualizer needs a fifo audio output
    # mopidy is not writing, and the media library builds itself from `list
    # album` / `list artist`, which mopidy-mpd answers empty. Browser and
    # search (`/`) both work, and the browser is the way into the library.
    ncmpcpp = {
      enable = true;
      settings = {
        mpd_host = "127.0.0.1";
        mpd_port = 6600;
        # The library hangs off a single "Subsonic" directory
        # (Albums / Artists / Directories), reachable only from here.
        startup_screen = "browser";
        user_interface = "alternative";
        autocenter_mode = true;
        # mopidy fetches over the network -- a seek per keystroke while the
        # key repeats would queue up a request each time.
        incremental_seeking = false;
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
      enable = false;
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
    rio = {
      enable = true;
      settings = {
        # Mod4+Shift+q asks the window to close, and rio's default answer is a
        # y/n prompt of its own — unconditionally, whether or not anything is
        # running in the shell. Closing an idle terminal is not a question.
        confirm-before-quit = false;
        # "Plain" is rio 0.5.24's no-tabs navigation mode (the only other
        # value is "Tab"): no tab bar, and the tab keybindings are inert.
        # The compositor already handles windowing.
        navigation = {
          mode = "Plain";
        };
        cursor = {
          shape = "block";
          blinking = false;
        };
        padding-x = 0;
        padding-y = 0;
        fonts = {
          additional-dirs = [ "/run/current-system/sw/share/X11/fonts" ];
        };
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
            options.nixos.expr = "(builtins.getFlake \"/etc/nixos\").nixosConfigurations.${osConfig.networking.hostName}.options";
          };
        };
      };
      settings = {
        theme = lib.mkForce "default";
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
    waybar = {
      enable = true;
      # sway spawns waybar itself via the `bars` block in sway.nix, which is
      # what makes `mode = "hide"` and the Mod4 reveal work. A systemd unit on
      # top of that just gets us a second, bar-id-less instance on every switch.
      systemd.enable = false;
      style = ''
        * {
          border: none;
          border-radius: 0;
          font-family: "FiraCode Nerd Font", "Fira Code", monospace;
          font-size: 13px;
          font-weight: bold;
          min-height: 0;
        }

        window#waybar {
          background-color: transparent;
          color: #cdd6f4;
        }

        #workspaces {
          background-color: rgba(17, 17, 27, 0.6);
          margin: 3px 6px;
          padding: 0 4px;
          border-radius: 10px;
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        #workspaces button {
          padding: 2px 10px;
          margin: 2px 2px;
          background-color: transparent;
          color: #a6adc8;
          border-radius: 8px;
          transition: all 0.2s ease-in-out;
        }

        #workspaces button:hover {
          background-color: rgba(137, 180, 250, 0.2);
          color: #cdd6f4;
        }

        #workspaces button.focused {
          background-color: #89b4fa;
          color: #11111b;
        }

        #workspaces button.active {
          background-color: #b4befe;
          color: #11111b;
        }

        #workspaces button.urgent {
          background-color: #f38ba8;
          color: #11111b;
        }

        #window {
          background-color: rgba(17, 17, 27, 0.6);
          padding: 3px 12px;
          margin: 3px 6px;
          border-radius: 10px;
          color: #cdd6f4;
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        window#waybar.empty #window {
          background-color: transparent;
          border: none;
          padding: 0;
          margin: 0;
        }

        #taskbar {
          background-color: rgba(17, 17, 27, 0.6);
          padding: 2px 6px;
          margin: 3px 6px;
          border-radius: 10px;
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        #taskbar button {
          padding: 2px 6px;
          margin: 0 2px;
          background-color: transparent;
          border-radius: 6px;
          border-bottom: 2px solid transparent;
          transition: all 0.2s ease-in-out;
        }

        #taskbar button:hover {
          background-color: rgba(255, 255, 255, 0.1);
        }

        #taskbar button.active {
          background-color: rgba(137, 180, 250, 0.25);
          border-bottom: 2px solid #89b4fa;
        }

        #mpris {
          background-color: rgba(180, 190, 254, 0.15);
          color: #cba6f7;
          padding: 3px 12px;
          margin: 3px 4px;
          border-radius: 10px;
          border: 1px solid rgba(203, 166, 247, 0.3);
        }

        #pulseaudio {
          background-color: rgba(148, 226, 213, 0.15);
          color: #94e2d5;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(148, 226, 213, 0.3);
        }

        #pulseaudio.muted {
          background-color: rgba(88, 91, 112, 0.2);
          color: #a6adc8;
          border-color: rgba(166, 173, 200, 0.2);
        }

        #pulseaudio.source {
          background-color: rgba(245, 194, 231, 0.15);
          color: #f5c2e7;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(245, 194, 231, 0.3);
        }

        #pulseaudio.source-muted {
          background-color: rgba(88, 91, 112, 0.2);
          color: #a6adc8;
          border-color: rgba(166, 173, 200, 0.2);
        }

        #network {
          background-color: rgba(166, 227, 161, 0.15);
          color: #a6e3a1;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(166, 227, 161, 0.3);
        }

        #network.disconnected, #network.disabled {
          background-color: rgba(243, 139, 168, 0.15);
          color: #f38ba8;
          border-color: rgba(243, 139, 168, 0.3);
        }

        #network.linked {
          background-color: rgba(249, 226, 175, 0.15);
          color: #f9e2af;
          border-color: rgba(249, 226, 175, 0.3);
        }

        #disk {
          background-color: rgba(137, 220, 235, 0.15);
          color: #89dceb;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(137, 220, 235, 0.3);
        }

        #memory {
          background-color: rgba(250, 179, 135, 0.15);
          color: #fab387;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(250, 179, 135, 0.3);
        }

        #custom-amd_gpu {
          background-color: rgba(235, 160, 172, 0.15);
          color: #eba0ac;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(235, 160, 172, 0.3);
        }

        #temperature {
          background-color: rgba(249, 226, 175, 0.15);
          color: #f9e2af;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(249, 226, 175, 0.3);
        }

        #temperature.critical {
          background-color: rgba(243, 139, 168, 0.25);
          color: #f38ba8;
          border-color: rgba(243, 139, 168, 0.5);
        }

        #cpu {
          background-color: rgba(114, 135, 253, 0.15);
          color: #7287fd;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(114, 135, 253, 0.3);
        }

        #custom-load {
          background-color: rgba(180, 190, 254, 0.15);
          color: #b4befe;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(180, 190, 254, 0.3);
        }

        #clock {
          background-color: rgba(203, 166, 247, 0.2);
          color: #cba6f7;
          padding: 3px 12px;
          margin: 3px 6px;
          border-radius: 10px;
          border: 1px solid rgba(203, 166, 247, 0.4);
        }

        #battery {
          background-color: rgba(166, 227, 161, 0.15);
          color: #a6e3a1;
          padding: 3px 10px;
          margin: 3px 3px;
          border-radius: 10px;
          border: 1px solid rgba(166, 227, 161, 0.3);
        }

        #battery.critical {
          background-color: rgba(243, 139, 168, 0.25);
          color: #f38ba8;
          border-color: rgba(243, 139, 168, 0.5);
        }

        #battery.charging {
          background-color: rgba(166, 227, 161, 0.15);
          color: #a6e3a1;
          border-color: rgba(166, 227, 161, 0.3);
        }

        #tray {
          background-color: rgba(17, 17, 27, 0.6);
          padding: 3px 10px;
          margin: 3px 6px;
          border-radius: 10px;
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        #mode {
          background-color: #f38ba8;
          color: #11111b;
          padding: 3px 10px;
          margin: 3px 6px;
          border-radius: 10px;
          font-weight: bold;
        }
      '';
    };
    firefox = {
      enable = true;
      package = inputs.chaotic.packages.${pkgs.stdenv.hostPlatform.system}.firefox_nightly;
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
          "media.peerconnection.enabled" = true;
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = true;
          "privacy.trackingprotection.fingerprinting.enabled" = true;
          "privacy.trackingprotection.cryptomining.enabled" = true;
          "dom.netinfo.enabled" = false;
          "media.video_stats.enabled" = true;
          "dom.gamepad.enabled" = false;
          "device.sensors.enabled" = false;
          "geo.enabled" = false;
          "privacy.query_stripping.enabled" = true;
          "browser.send_pings" = false;
          "dom.security.https_only_mode" = true;
          "browser.search.suggest.enabled" = false;
          "network.dns.disablePrefetch" = true;
          "network.prefetch-next" = false;
          "network.http.speculative-parallel-limit" = 0;
          "network.predictor.enabled" = false;
          "gfx.webrender.all" = true;
          "webgl.disabled" = false;
          "webgl.force-enabled" = true;
          "layers.acceleration.force-enabled" = true;
          # Read the colour scheme from the portal rather than from GTK.
          # The default is 2, "auto", which means the portal is only read
          # inside a sandbox; a native build follows GTK/dconf instead, which
          # is static. Reading the portal is what makes the compositor's own
          # dark-mode toggle reach a running Firefox.
          "widget.use-xdg-desktop-portal.settings" = 1;
          # resistFingerprinting spoofs prefers-color-scheme as light, on
          # purpose, so a site cannot fingerprint the theme — which is why
          # every page rendered light here no matter what the portal said.
          # fingerprintingProtection is the targeted successor and does not
          # lie about the colour scheme.
          "privacy.resistFingerprinting" = false;
          "privacy.fingerprintingProtection" = true;
        };
      };
    };
    mpv = {
      enable = true;
      scripts = with pkgs.mpvScripts; [
        uosc
        thumbfast
        autoload
      ];
      config = {
        save-position-on-quit = true;
        resume-playback = true;
      };
      profiles = {
        anime = {
          profile = "gpu-hq";
          deband = true;
          deband-iterations = 4;
          deband-threshold = 48;
          deband-range = 16;
          deband-grain = 48;
          dither-depth = "auto";
          alang = "jpn,jap,eng,en";
          slang = "jpn,jap,eng,en";
          sub-auto = "fuzzy";
          sub-file-paths = "ass:srt:sub:subs:subtitles";
          demuxer-mkv-subtitle-preroll = true;
          glsl-shaders = "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl:${pkgs.anime4k}/Anime4K_Restore_CNN_VL.glsl:${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_VL.glsl:${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl:${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl:${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl";
        };
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
    fish = {
      enable = true;
      # A long agent run tied to a terminal window dies with the window. This
      # puts it in a session of its own, named after the repo, so closing the
      # terminal detaches instead of killing: `agent claude`, `agent hermes`,
      # or bare `agent` for a shell. Already inside tmux, it switches to that
      # session rather than nesting one inside another.
      #
      # The command is part of the session name: with the repo alone, a second
      # `agent hermes` in a repo that already has `agent claude` running would
      # attach to the claude session and silently drop its own arguments.
      functions.agent = {
        description = "Attach or create a detached-safe tmux session for this repo";
        body = ''
          set -l root (git rev-parse --show-toplevel 2>/dev/null)
          test -n "$root"; or set root $PWD
          set -l name agent-(basename $root)
          test (count $argv) -gt 0; and set name $name-(basename $argv[1])

          if set -q TMUX
            tmux has-session -t "=$name" 2>/dev/null
            or tmux new-session -d -s $name -c $root $argv
            tmux switch-client -t "=$name"
          else
            tmux new-session -A -s $name -c $root $argv
          end
        '';
      };
      interactiveShellInit = ''
        set fish_greeting ""
        set -gx PATH $PATH /home/codebam/.local/bin /home/codebam/.cargo/bin /home/codebam/.npm-global/bin /home/codebam/.kimi-code/bin
        set -gx SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
        set -gx SEARXNG_API_URL http://127.0.0.1:8081
        set -gx SEARXNG_URL http://127.0.0.1:8081
        set -gx EDITOR hx
        set -gx NIXOS_OZONE_WL 1
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
    # gh rewrites config.yml on most invocations, replacing home-manager's
    # symlink with a plain file; force = true (below, in xdg.configFile) keeps
    # activation from failing on it. hosts.yml stays unmanaged — that is where
    # the auth state lives.
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        prompt = "enabled";
        aliases = {
          co = "pr checkout";
        };
      };
    };
    # Base options and key bindings come from home/shell-common.nix.
    tmux = {
      extraConfig = ''
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
        {
          # resurrect alone only saves when you press prefix C-s, which is
          # never the moment the machine actually goes down. continuum saves on
          # a timer and restores on tmux start.
          #
          # Deliberately no agent binary in @resurrect-processes: a restored
          # `claude` or `hermes` comes back with no conversation and looks
          # alive. @resurrect-capture-pane-contents (above) keeps the
          # transcript, which is the part worth having back.
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '10'
          '';
        }
      ];
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
        # No hibernate entry: the GPT swap partitions are no longer
        # activated, the remaining swapfile is 2G, and boot.resumeDevice is
        # unset, so `systemctl hibernate` cannot save an image. Re-add once
        # swap is at least RAM-sized and resumeDevice points at it.
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
