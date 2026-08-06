{ pkgs, lib, ... }:

{
  # Module definitions shared by every host. Hosts add their own
  # `modules-right` (and `modules-center`) plus any host-specific blocks:
  # battery on laptop/deck, network/mpris/temperature/amd_gpu on the desktop.
  programs.waybar.settings.mainBar = {
    ipc = true;

    layer = "top";

    position = "top";

    height = 30;

    modules-left = [
      "ext/workspaces"
      "wlr/taskbar"
    ];

    "ext/workspaces" = {
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
        default = [
          ""
          ""
          ""
        ];
      };
      on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
    };

    "disk" = {
      path = "/";
      interval = 60;
      format = " 󰋊 /: {free} ";
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

    "memory" = {
      interval = 5;
      # mkDefault so the desktop can swap in its "% (used GiB)" variant.
      format = lib.mkDefault " 󰍛 {percentage}% ";
    };

    # Defined for every host but only listed in modules-right on the machines
    # that have a battery; waybar never instantiates an unlisted module.
    "battery" = {
      states = {
        warning = 20;
        critical = 10;
      };
      format = " {icon} {capacity}% ";
      format-charging = " 󰂄 {capacity}% ";
      format-plugged = " 󰂄 {capacity}% ";
      format-icons = [
        "󰂎"
        "󰁺"
        "󰁻"
        "󰁼"
        "󰁽"
        "󰁾"
        "󰁿"
        "󰂀"
        "󰂁"
        "󰂂"
        "󰁹"
      ];
    };
  };
}
