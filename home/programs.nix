{ pkgs, lib, ... }:

{
  programs = {
    mnw = {
      enable = true;
      neovim = pkgs.neovim-unwrapped;
      aliases = [
        "vi"
        "vim"
      ];
      initLua = ''
        require('codebam')
      '';
      providers = {
        ruby.enable = false;
        python3.enable = false;
      };
      plugins = {
        dev.codebam = {
          pure = ../nvim;
        };
        start = with pkgs.vimPlugins; [
          avante-nvim
          blink-cmp
          blink-cmp-copilot
          catppuccin-vim
          commentary
          conform-nvim
          copilot-lua
          friendly-snippets
          git-blame-nvim
          gitsigns-nvim
          lazydev-nvim
          lualine-nvim
          luasnip
          neogit
          nvim-autopairs
          nvim-bqf
          nvim-surround
          nvim-treesitter.withAllGrammars
          nvim-treesitter-textobjects
          nvim-web-devicons
          oil-nvim
          plenary-nvim
          sensible
          sleuth
          telescope-nvim
          todo-comments-nvim
          treesj
        ];
      };
      extraLuaPackages = ps: [ ps.jsregexp ];
      extraBinPath = with pkgs; [
        bash-language-server
        nil
        nixd
      ];
    };
    neovide = {
      enable = false;
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
        prepend /home/myuser/.apps |
        append /usr/bin/env
        )
        $env.SSH_AUTH_SOCK = (gpgconf --list-dirs agent-ssh-socket)
        $env.GPG_TTY = (tty)
      '';
    };
    i3status-rust = {
      enable = true;
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
    obs-studio = {
      enable = true;
      plugins = [ pkgs.obs-studio-plugins.obs-vaapi ];
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
        set -gx NIXOS_OZONE_WL 1
        set -gx OBS_VKCAPTURE 1
        set -gx WLR_RENDERER vulkan
        set -gx MANGOHUD_CONFIGFILE /home/codebam/.config/MangoHud/MangoHud.conf
        set -gx PROTON_ENABLE_WAYLAND 1
        set -gx PROTON_ENABLE_HDR 1
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
      userEmail = "codebam@riseup.net";
      userName = "Sean Behan";
      extraConfig = {
        merge = {
          tool = "nvimdiff";
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
        set -sg escape-time 300
      '';
    };

    foot = {
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
          command = "${pkgs.pipewire}/bin/pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/bell.oga";
          command-focused = "yes";
        };
        colors = {
          alpha = lib.mkForce 0.9;
        };
      };
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = false;
      enableBashIntegration = true;
      enableFishIntegration = true;
      defaultOptions = [
        "--no-height"
        "--no-reverse"
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
    };
  };
}
