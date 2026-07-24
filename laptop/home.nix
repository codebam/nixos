{ pkgs, ... }:

{
  programs = {
    git = {
      signing = {
        key = "097B3E3F284C7B4C";
        signByDefault = true;
      };
    };
    bash = {
      profileExtra = ''
        PATH="$HOME/.local/bin:$PATH"
        export PATH
      '';
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
