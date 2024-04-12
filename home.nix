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
    includes = [
      {
        contents = {
          user = {
            email = "codebam@riseup.net";
            name = "Sean Behan";
            signingKey = "0F6D5021A87F92BA";
          };
          commit = {
            gpgSign = true;
          };
        };
      }
    ];
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