{ config, pkgs, lib, ... }:

{
  home.username = "codebam";
  home.homeDirectory = "/home/codebam";
  wayland.windowManager.sway = let
    wallpaper = builtins.fetchurl {
      url = "https://images.hdqwalls.com/download/1/beach-seaside-digital-painting-4k-05.jpg";
      sha256 = "2877925e7dab66e7723ef79c3bf436ef9f0f2c8968923bb0fff990229144a3fe";
    };
    modifier = "Mod4";
  in {
    extraConfigEarly = ''
      set $rosewater #f5e0dc
      set $flamingo #f2cdcd
      set $pink #f5c2e7
      set $mauve #cba6f7
      set $red #f38ba8
      set $maroon #eba0ac
      set $peach #fab387
      set $yellow #f9e2af
      set $green #a6e3a1
      set $teal #94e2d5
      set $sky #89dceb
      set $sapphire #74c7ec
      set $blue #89b4fa
      set $lavender #b4befe
      set $text #cdd6f4
      set $subtext1 #bac2de
      set $subtext0 #a6adc8
      set $overlay2 #9399b2
      set $overlay1 #7f849c
      set $overlay0 #6c7086
      set $surface2 #585b70
      set $surface1 #45475a
      set $surface0 #313244
      set $base #1e1e2e
      set $mantle #181825
      set $crust #11111b
    '';
    enable = true;
    systemd.enable = true;
    config = rec {
      inherit modifier;
      terminal = "foot"; 
      menu = "wofi";
      fonts = {
        names = [ "Noto Sans" "FontAwesome" ];
        style = "Bold Semi-Condensed";
        size = 11.0;
      };
      colors = {
        focused = {
          background = "$lavender";
          border = "$base";
          childBorder = "$lavender";
          indicator = "$rosewater";
          text = "$text";
        };
        focusedInactive = {
          background = "$overlay0";
          border = "$base";
          childBorder = "$overlay0";
          indicator = "$rosewater";
          text = "$text";
        };
        unfocused = {
          background = "$overlay0";
          border = "$base";
          childBorder = "$overlay0";
          indicator = "$rosewater";
          text = "$text";
        };
        urgent = {
          background = "$peach";
          border = "$base";
          childBorder = "$peach";
          indicator = "$overlay0";
          text = "$peach";
        };
        placeholder = {
          background = "$overlay0";
          border = "$base";
          childBorder = "$overlay0";
          indicator = "$overlay0";
          text = "$text";
        };
        background = "$base";
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
        colors = {
          background = "$base";
          statusline = "$text";
          focusedStatusline = "$text";
          focusedSeparator = "$base";
          focusedWorkspace = {
            background = "$base";
            border = "$base";
            text = "$green";
          };
          activeWorkspace = {
            background = "$base";
            border = "$base";
            text = "$blue";
          };
          inactiveWorkspace = {
            background = "$base";
            border = "$base";
            text = "$surface1";
          };
          urgentWorkspace = {
            background = "$base";
            border = "$base";
            text = "$surface1";
          };
          bindingMode = {
            background = "$base";
            border = "$base";
            text = "$surface1";
          };
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
      keybindings = let inherit modifier; in lib.mkOptionDefault {
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
    extraConfig = let inherit modifier; in ''
        bindsym --whole-window {
          ${modifier}+button4 exec "wpctl set-volume @DEFAULT_SINK@ 1%+"
          ${modifier}+button5 exec "wpctl set-volume @DEFAULT_SINK@ 1%-"
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
            block = "sound";
            format = "$volume";
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
          node ~/git/cloudflare-ai-cli/src/client.mjs "$@"
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
