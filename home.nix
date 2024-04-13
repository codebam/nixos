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
          bg = "~/Pictures/wallpapers/wallpaper.png fill";
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
  programs.bash = {
    enable = true;
    initExtra = ''
      command_not_found_handle() {
          node ~/git/damp-recipe-a17d/src/client.mjs "$@"
      }
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
      colorscheme nord
      let g:lightline = {
            \ 'colorscheme': 'nord',
            \ }
      let g:coc_disable_startup_warning = 1
      let g:coc_global_extensions = [
            \ 'coc-tsserver',
            \ 'coc-rust-analyzer',
            \ 'coc-prettier',
            \ 'coc-eslint',
            \ 'coc-texlab',
            \ 'coc-go',
            \ 'coc-rust-analyzer',
            \ 'coc-json',
            \ 'coc-html',
            \ 'coc-tailwindcss',
            \ 'coc-snippets',
            \ 'coc-svelte',
            \ 'coc-python',
        \ ]
    '';
    plugins = [
      pkgs.vimPlugins.sensible
      pkgs.vimPlugins.coc-nvim
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
      pkgs.vimPlugins.nord-vim
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
  };
  programs.waybar = {
    enable = true;
  };
  programs.foot = {
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
      colors = {
        foreground = "d8dee9";
        background = "2e3440";
        regular0 = "3b4252";
        regular1 = "bf616a";
        regular2 = "a3be8c";
        regular3 = "ebcb8b";
        regular4 = "81a1c1";
        regular5 = "b48ead";
        regular6 = "88c0d0";
        regular7 = "e5e9f0";
        bright0 = "4c566a";
        bright1 = "bf616a";
        bright2 = "a3be8c";
        bright3 = "ebcb8b";
        bright4 = "81a1c1";
        bright5 = "b48ead";
        bright6 = "8fbcbb";
        bright7 = "eceff4";
        dim0 = "373e4d";
        dim1 = "94545d";
        dim2 = "809575";
        dim3 = "b29e75";
        dim4 = "68809a";
        dim5 = "8c738c";
        dim6 = "6d96a5";
        dim7 = "aeb3bb";
      };
    };
  };
  programs.wofi = {
    enable = true;
    settings = {
      show = "drun";
      dmenu = true;
      insentitive = true;
      prompt = "";
      width = "25%";
      lines = 5;
      location = "center";
      hide_scroll = true;
    };
  };
  services.mako = {
    enable = true;
    layer = "overlay";
    font = "Noto Sans";
    defaultTimeout = 5000;
  };

  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
}
