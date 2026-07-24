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
    waybar.settings.mainBar = {
      ipc = true;
      layer = "top";
      position = "top";
      height = 30;
      modules-left = [
        "sway/workspaces"
        "wlr/taskbar"
      ];
      modules-right = [
        "pulseaudio"
        "disk"
        "memory"
        "cpu"
        "custom/load"
        "clock"
        "battery"
      ];

      "sway/workspaces" = {
        disable-scroll = false;
        enable-bar-scroll = true;
        all-outputs = true;
        format = "{name}";
      };

      "sway/window" = {
        format = "{icon} {title}";
        max-length = 40;
        icon = true;
        icon-size = 16;
      };

      "wlr/taskbar" = {
        format = "{icon}";
        icon-size = 16;
        tooltip-format = "{title}";
        on-click = "activate";
        on-click-middle = "close";
      };

      "pulseaudio" = {
        format = " {icon} {volume}% ";
        format-muted = " 󰝟 muted ";
        format-icons = {
          default = [ "" "" "" ];
        };
        on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      };

      "disk" = {
        path = "/";
        interval = 60;
        format = " 󰋊 /: {free} ";
      };

      "memory" = {
        interval = 5;
        format = " 󰍛 {percentage}% ";
      };

      "cpu" = {
        interval = 5;
        format = "  {usage}% ";
      };

      "custom/load" = {
        exec = "${pkgs.coreutils}/bin/cat /proc/loadavg | ${pkgs.gawk}/bin/awk '{print $1}'";
        interval = 5;
        format = " 󰓅 {} ";
      };

      "clock" = {
        interval = 60;
        format = " 󰥔 {:%a %b %d, %H:%M} ";
      };

      "battery" = {
        states = {
          warning = 20;
          critical = 10;
        };
        format = " {icon} {capacity}% ";
        format-charging = " 󰂄 {capacity}% ";
        format-plugged = " 󰂄 {capacity}% ";
        format-icons = [ "󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
      };
    };
  };
}
