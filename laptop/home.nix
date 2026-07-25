_:

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
      modules-right = [
        "pulseaudio"
        "disk"
        "memory"
        "cpu"
        "custom/load"
        "clock"
        "battery"
      ];

      "memory" = {
        interval = 5;
        format = " 󰍛 {percentage}% ";
      };

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
  };
}
