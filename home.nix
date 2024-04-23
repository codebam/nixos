{ config, pkgs, lib, ... }:

let
  wallpaper = builtins.fetchurl {
    url = "https://images.hdqwalls.com/download/1/beach-seaside-digital-painting-4k-05.jpg";
    sha256 = "2877925e7dab66e7723ef79c3bf436ef9f0f2c8968923bb0fff990229144a3fe";
  };
in
{
  home.username = "codebam";
  home.homeDirectory = "/home/codebam";
  wayland.windowManager.sway = {
    enable = true;
    systemd.enable = true;
    config = rec {
      modifier = "Mod4";
      terminal = "foot"; 
      menu = "wofi";
      startup = [
        {
          command = "${pkgs.systemd}/bin/systemctl --user restart polkit-gnome-authentication-agent-1.service";
          always = true;
        }
      ];
      fonts = {
        names = [ "Noto Sans" "FontAwesome" ];
        style = "Bold Semi-Condensed";
        size = 11.0;
      };
      output = {
        "*" = {
          bg = "${wallpaper} fill";
        };
        "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
          mode = "3840x1600@143.998Hz";
          adaptive_sync = "on";
          subpixel = "none";
        };
      };
      bars = [{
        position = "top";
        statusCommand = "i3status-rs ~/.config/i3status-rust/config-default.toml";
        hiddenState = "hide";
        trayOutput = "none";
        fonts = {
          names = [ "Fira Code" "FontAwesome" ];
          style = "Bold Semi-Condensed";
          size = 11.0;
        };
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
        "${modifier}+n" = "exec 'swaymsg \"bar mode toggle\"'";
      };
    };
    extraConfig = ''
        bindsym --whole-window {
          Mod4+button4 exec "wpctl set-volume @DEFAULT_SINK@ 1%+"
          Mod4+button5 exec "wpctl set-volume @DEFAULT_SINK@ 1%-"
        }
    '';
  };
  programs.i3status-rust = {
    enable = true;
    bars = {
      default = {
        settings = {
          theme = {
            theme = "ctp-mocha";
          };
        };
        icons = "awesome6";
        blocks = [
          {
            block = "focused_window";
          }
          {
            alert = 10.0;
            block = "disk_space";
            info_type = "available";
            interval = 60;
            path = "/";
            warning = 20.0;
          }
          {
            block = "memory";
            format = " $icon $mem_used_percents ";
          }
          {
            block = "cpu";
          }
          {
            block = "amd_gpu";
          }
          {
            block = "load";
          }
          {
            block = "net";
          }
          {
            block = "external_ip";
          }
          {
            block = "temperature";
          }
          {
            block = "time";
            interval = 60;
          }
        ];
      };
    };
  };
  programs.swaylock = {
    enable = true;
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
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        font = "Fira Code Nerdfont:size=11";
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
    defaultTimeout = 5000;
  };
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  gtk = {
    enable = true;
  };

  xdg = {
    enable = true;
  };

  catppuccin = {
    enable = true;
    flavour = "mocha";
  };

  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
}
