{ config, pkgs, ... }:

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
        border = 1;
      };
      gaps = {
        inner = 15;
        smartGaps = true;
      };
      focus.followMouse = false;
      workspaceAutoBackAndForth = true;
    };
  };
  programs.bash = {
    enable = true;
  };
  programs.vim = {
    enable = true;
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
