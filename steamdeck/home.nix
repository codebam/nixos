{
  pkgs,
  lib,
  config,
  ...
}:

{
  stylix = {
    targets = {
      qt.enable = lib.mkForce false;
    };
  };

  home = {
    file.".config/lsfg-vk/conf.toml".text = ''
      version = 1
      [global]
      [[game]]
      exe = "decky-lsfg-vk"
      multiplier = 3
      performance_mode = true
    '';
    packages = with pkgs; [
      prismlauncher
      moonlight-qt
      wvkbd
      (writeShellScriptBin "lsfg" ''
        export LSFG_PROCESS=decky-lsfg-vk
        exec "$@"
      '')
    ];
  };

  wayland.windowManager.sway =
    let
      modKey = "Mod1";
    in
    {
      config = {
        modifier = lib.mkForce modKey;
        output = {
          "eDP-1" = {
            transform = "90";
          };
          "X11-1" = {
            resolution = "1280x800";
          };
        };
        input = {
          "type:touch" = {
            map_to_output = "eDP-1";
          };
        };
        keybindings = lib.mkOptionDefault {
          "${modKey}+k" = "exec pkill --signal SIGRTMIN wvkbd-mobintl || wvkbd-mobintl -L 250";
          "F11" = "exec pkill --signal SIGRTMIN wvkbd-mobintl || wvkbd-mobintl -L 250";
          "F12" = "exec ${config.wayland.windowManager.sway.config.menu}";
          "F9" = "workspace prev";
          "F10" = "workspace next";
          "F8" =
            "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY; swaymsg exit'";
          "Ctrl+Alt+BackSpace" =
            "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY; swaymsg exit'";
          "XF86PowerOff" = "exec systemctl suspend";
        };
        window = {
          commands = [
            {
              command = "floating enable, sticky enable, focus_on_window_activation none";
              criteria = {
                app_id = "wvkbd";
              };
            }
          ];
        };
        startup = [
          { command = "steam -silent -desktop"; }
        ];
      };
    };

  dconf.settings = {
    "org/gnome/desktop/a11y/applications" = {
      screen-keyboard-enabled = true;
    };
  };

  programs = {
    git = {
      signing = {
        key = "0F6D5021A87F92BA";
        signByDefault = true;
      };
    };
    i3status-rust = {
      bars = {
        default = {
          blocks = [
            { block = "focused_window"; }
            { block = "sound"; }
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
            { block = "cpu"; }
            { block = "load"; }
            {
              block = "time";
              interval = 60;
            }
            { block = "battery"; }
          ];
        };
      };
    };
  };
}
