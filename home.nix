{ config, pkgs, lib, ... }:

{
  home.username = "codebam";
  home.homeDirectory = "/home/codebam";
  wayland.windowManager.sway = {
    enable = true;
    config = rec {
      modifier = "Mod4";
      terminal = "foot"; 
      menu = "wofi";
      fonts = {
        names = [ "Noto Sans" "FontAwesome" ];
        style = "Bold Semi-Condensed";
        size = 11.0;
      };
      output = {
        "*" = {
          bg = "${builtins.fetchurl { url = "https://images.hdqwalls.com/download/1/beach-seaside-digital-painting-4k-05.jpg"; sha256 = "2877925e7dab66e7723ef79c3bf436ef9f0f2c8968923bb0fff990229144a3fe"; }} fill";
        };
        "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
          mode = "3840x1600@143.998Hz";
          adaptive_sync = "on";
          max_render_time = "1";
          subpixel = "none";
        };
      };
      bars = [{
        command = "waybar";
      }];
      window = {
        titlebar = false;
        border = 1;
        hideEdgeBorders = "smart";
      };
      floating = {
        titlebar = false;
        border = 1;
      };
      gaps = {
        inner = 15;
        smartGaps = true;
      };
      focus.followMouse = false;
      workspaceAutoBackAndForth = true;
      keybindings = let modifier = config.wayland.windowManager.sway.config.modifier; in lib.mkOptionDefault {
        "${modifier}+p" = "exec swaylock";
        "${modifier}+shift+u" = "exec playerctl play-pause";
        "${modifier}+shift+y" = "exec playerctl previous";
        "${modifier}+shift+i" = "exec playerctl next";
        "Control+space" = "exec makoctl dismiss";
        "${modifier}+Control+space" = "exec makoctl restore";
        "${modifier}+shift+x" = "exec ~/.local/bin/screenshot";
        "${modifier}+x" = "exec ~/.local/bin/screenshot-select";
      };
    };
  };
  programs.swaylock = {
    enable = true;
    settings = {
      color = "#000000";
      ring-color = "#000000";
    };
  };
  programs.bash = {
    enable = true;
    initExtra = ''
      command_not_found_handle() {
          node ~/git/damp-recipe-a17d/src/client.mjs "$@"
      }
    '';
    profileExtra = ''
      PATH="$HOME/.local/bin:$PATH"
      export PATH
      WLR_RENDERER=vulkan
      export WLR_RENDERER
    '';
  };
  programs.vim = {
    enable = true;
    defaultEditor = true;
    settings = {
      background = "dark";
      expandtab = true;
      ignorecase = true;
      shiftwidth = 4;
      smartcase = true;
      tabstop = 8;
      undodir = ["$HOME/.vim/undodir"];
    };
    extraConfig = ''
      colorscheme catppuccin_mocha
      let g:lightline = {
            \ 'colorscheme': 'catppuccin_mocha',
            \ }
      let g:coc_disable_startup_warning = 1
    '';
    plugins = [
      pkgs.vimPlugins.sensible
      pkgs.vimPlugins.coc-nvim
      pkgs.vimPlugins.coc-python
      pkgs.vimPlugins.coc-prettier
      pkgs.vimPlugins.coc-eslint
      pkgs.vimPlugins.coc-snippets
      pkgs.vimPlugins.coc-json
      pkgs.vimPlugins.coc-svelte
      pkgs.vimPlugins.commentary
      pkgs.vimPlugins.sleuth
      pkgs.vimPlugins.surround
      pkgs.vimPlugins.fugitive
      pkgs.vimPlugins.gitgutter
      pkgs.vimPlugins.vim-javascript
      pkgs.vimPlugins.vim-javascript
      pkgs.vimPlugins.typescript-vim
      pkgs.vimPlugins.lightline-vim
      pkgs.vimPlugins.vim-startify
      pkgs.vimPlugins.todo-comments-nvim
      pkgs.vimPlugins.vim-snippets
      pkgs.vimPlugins.catppuccin-vim
    ];
  };
  programs.git = {
    enable = true;
    userEmail = "codebam@riseup.net";
    userName = "Sean Behan";
    signing = {
      key = "0F6D5021A87F92BA";
      signByDefault = true;
    };
  };
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",*256col*:Tc"
      set -g @plugin 'tmux-plugins/tpm'
      set -g @plugin 'tmux-plugins/tmux-sensible'
      set -g @plugin 'tmux-plugins/tmux-resurrect'
      unbind C-b
      set -g prefix C-a
      bind C-a send-prefix
      bind-key C-a last-window
      bind-key a send-prefix
      bind-key b set status
      bind s split-window -v
      bind v split-window -h
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      set -g mouse
      run '~/.tmux/plugins/tpm/tpm'
    '';
  };
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        height = 30;
        modules-left = [ "sway/workspaces" "sway/mode" "wlr/taskbar" "sway/window" ];
        modules-center = [ "clock" "clock#1" ];
        modules-right = [ "wireplumber" "memory" "cpu" "disk" "network" ];
        "clock#1" = {
          format = "{:%m-%d}";
        };
        network = {
          interval = 1;
          format-wifi = " {signalStrength}%";
          format-ethernet = " {ifname}";
          format-disconnected = "No Network";
        };
        disk = {
          interval = 1;
          format = " {}%";
        };
        cpu = {
          interval = 1;
          format = " {}";
        };
        memory = {
          interval = 1;
          format = " {}%";
        };
        wireplumber = {
          format = "{icon} {volume:2}%";
          format-muted = "MUTE";
          scroll-step = 1;
        };
        clock = {
          interval = 60;
          tooltip = true;
          format = "{:%H:%M}";
          tooltip-format = "{:%Y-%m-%d}";
        };
      };
    };
  };
  programs.foot = {
    catppuccin.enable = true;
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        font = "Fira Code:size=11";
        dpi-aware = "yes";
      };
      mouse = {
        hide-when-typing = "yes";
      };
      bell = {
        urgent = "yes";
        command = "pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/bell.oga";
        command-focused = "yes";
      };
    };
  };
  programs.wofi = {
    enable = true;
    settings = {
      show = "drun";
      dmenu = true;
      insensitive = true;
      prompt = "";
      width = "25%";
      lines = 5;
      location = "center";
      hide_scroll = true;
    };
    style = ''
      window {
        margin: 4px;
        background-color: rgba(0,0,0,0);
      }
      #input {
        margin-left: 4px;
        margin-right: 4px;
        color: #E5E9F0;
        background-color: #2E3440;
        box-shadow: none;
        border: 1px solid #88c0d0;
        border-radius: 0px;
      }
      #inner-box {
        border-radius: 4px 4px 4px 4px;
        background-color: #2E3440;
        border 1px solid #3B4252;
      }
      #outer-box {
        margin: 4px;
      }
      #scroll {
        margin: 4px;
      }
      #entry,
      #text {
        font-family: Fira Code;
        font-size: 9pt;
        color: #E5E9F0;
        outline-style: none;
      }
      #entry:selected {
        color: #2e3440;
        background-color: #88c0d0;
      }
      #entry:selected #text {
        color: #2e3440;
      }
      .left, .right {
        color: transparent;
      }
    '';
  };
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
  services.mako = {
    enable = true;
    layer = "overlay";
    font = "Noto Sans";
    backgroundColor = "#333333";
    borderColor = "#FFFFFF";
    borderRadius = 3;
    defaultTimeout = 5000;
  };
  catppuccin.flavour = "mocha";
  programs.fzf = {
    catppuccin.enable = true;
    enable = true;
    enableBashIntegration = true;
  };

  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
}
