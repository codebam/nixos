{
  pkgs,
  lib,
  inputs,
  ...
}:

{
  programs = {
    chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
    };
    ghostty = {
      enable = false;
      enableFishIntegration = true;
      clearDefaultKeybinds = true;
      settings = {
        cursor-style = "block";
        shell-integration-features = "no-cursor";
        background-opacity = 0.8;
        cursor-style-blink = false;
        window-padding-x = 0;
        window-padding-y = 0;
        app-notifications = "no-clipboard-copy";
      };
    };
    helix = {
      enable = true;
      package = inputs.helix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultEditor = true;
      settings = {
        theme = lib.mkForce "ayu_mirage";
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
                idle_fg = "#95e6cb";
                idle_bg = "#131721";
                good_fg = "#b8cc52";
                good_bg = "#131721";
                warning_fg = "#ffb454";
                warning_bg = "#272d38";
                critical_fg = "#f07178";
                critical_bg = "#272d38";
                info_fg = "#59c2ff";
                info_bg = "#131721";
                separator_fg = "#e6e1cf";
                separator_bg = "#131721";
                separator = "";
              };
            };
          };
          icons = "awesome6";
        };
      };
    };
    librewolf = {
      enable = true;
    };
    yt-dlp = {
      enable = true;
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
      settings = {
        preset = 4;
        gamemode = true;
        hdr = true;
        full = true;
      };
    };
    wezterm = {
      enable = true;
      extraConfig = ''
        return {
          window_background_opacity = 0.9,
          hide_tab_bar_if_only_one_tab = true,
          window_padding = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
          }
        }
      '';
    };
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };
    gh-dash = {
      enable = true;
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
        set -gx SEARXNG_API_URL http://localhost:8081
        set -gx EDITOR hx
        set -gx NIXOS_OZONE_WL 1
        # set -gx OBS_VKCAPTURE 1
        # set -gx WLR_RENDERER vulkan
        # set -gx MANGOHUD_CONFIGFILE /home/codebam/.config/MangoHud/MangoHud.conf
        # set -gx PROTON_ENABLE_WAYLAND 1
        # set -gx PROTON_ENABLE_HDR 1
        # set -gx PROTON_USE_NTSYNC 1
        function __hm_play_bell_on_postexec --on-event fish_postexec
          if test $status -eq 0
            tput bel
          else
            ${pkgs.pipewire}/bin/pw-play ${../error.wav}
          end
        end
      '';
      plugins = [
        {
          name = "autopair.fish";
          src = pkgs.fetchFromGitHub {
            owner = "jorgebucaran";
            repo = "autopair.fish";
            rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
            sha256 = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
          };
        }
        {
          name = "puffer-fish";
          src = pkgs.fetchFromGitHub {
            owner = "nickeb96";
            repo = "puffer-fish";
            rev = "12d062eae0ad24f4ec20593be845ac30cd4b5923";
            sha256 = "sha256-2niYj0NLfmVIQguuGTA7RrPIcorJEPkxhH6Dhcy+6Bk=";
          };
        }
      ];
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
    kitty = {
      enable = false;
      enableGitIntegration = true;
      shellIntegration = {
        mode = "no-cursor";
        enableBashIntegration = true;
        enableFishIntegration = true;
      };
      settings = {
        term = "xterm-256color";
        cursor_shape = "block";
        cursor_blink_interval = 0;
        background_opacity = lib.mkForce 0.8;
        mouse_hide_wait = 0;
        disable_ligatures = "cursor";
        cursor_trail = 1;
      };
    };
    foot = {
      server = {
        enable = true;
      };
      enable = true;
      settings = {
        main = {
          term = "xterm-256color";
        };
        mouse = {
          hide-when-typing = "yes";
        };
        bell = {
          urgent = "yes";
          command = "${pkgs.pipewire}/bin/pw-play ${../bell.wav}";
          command-focused = "yes";
        };
        colors.alpha = lib.mkForce 0.8;
      };
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
        scan_timeout = 10;
        character = {
          success_symbol = "\\$";
          error_symbol = "🔴";
        };
      };
    };
  };
}
