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
        "sway/window"
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
        disable-scroll = true;
        all-outputs = true;
        format = "{name}";
      };

      "sway/window" = {
        format = " {title}";
        max-length = 40;
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
