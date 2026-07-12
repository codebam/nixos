{
  pkgs,
  lib,
  config,
  ...
}:

{
  wayland.windowManager.sway =
    let
      modifier = "Mod4";
    in
    {
      enable = true;
      package = pkgs.sway_git;
      systemd.enable = true;
      wrapperFeatures.gtk = true;
      xwayland = true;
      config = rec {
        inherit modifier;
        terminal = "${pkgs.ghostty}/bin/ghostty";
        menu = "${pkgs.wmenu}/bin/wmenu-run -f \"Fira Code NerdFont 11\" -i -N 000000 -n cdd6f4 -M 000000 -m 89b4fa -S 89b4fa -s 000000";
        colors = {
          background = "#000000";
          focused = {
            border = "#89b4fa";
            background = "#000000";
            text = "#cdd6f4";
            indicator = "#f5e0dc";
            childBorder = "#89b4fa";
          };
          focusedInactive = {
            border = "#11111b";
            background = "#000000";
            text = "#a6adc8";
            indicator = "#11111b";
            childBorder = "#11111b";
          };
          unfocused = {
            border = "#000000";
            background = "#000000";
            text = "#585b70";
            indicator = "#000000";
            childBorder = "#000000";
          };
          urgent = {
            border = "#f38ba8";
            background = "#000000";
            text = "#f38ba8";
            indicator = "#f38ba8";
            childBorder = "#f38ba8";
          };
        };
        seat = {
          "*" = {
            # hide_cursor = "1000";
          };
        };
        output = { };
        input = {
          "*" = {
            events = "enabled";
            accel_profile = "flat";
          };
          "1739:0:Synaptics_TM3289-021" = {
            events = "enabled";
            dwt = "enabled";
            tap = "enabled";
            natural_scroll = "enabled";
            middle_emulation = "enabled";
            pointer_accel = "0.2";
            accel_profile = "adaptive";
          };
          "2:10:TPPS/2_Elan_TrackPoint" = {
            events = "enabled";
            pointer_accel = "0.7";
            accel_profile = "adaptive";
          };
        };
        bars = [
          {
            statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
            mode = "hide";
            fonts = lib.mkForce {
              names = [ "Fira Code NerdFont" ];
              size = 11.0;
            };
            position = "top";
            hiddenState = "hide";
            trayOutput = "none";
            colors = {
              background = lib.mkForce "#000000";
              statusline = lib.mkForce "#cdd6f4";
              separator = lib.mkForce "#45475a";
              focusedWorkspace = {
                border = "#89b4fa";
                background = "#000000";
                text = "#89b4fa";
              };
              activeWorkspace = {
                border = "#313244";
                background = "#000000";
                text = "#a6adc8";
              };
              inactiveWorkspace = {
                border = "#000000";
                background = "#000000";
                text = "#585b70";
              };
              urgentWorkspace = {
                border = "#f38ba8";
                background = "#000000";
                text = "#f38ba8";
              };
            };
          }
        ];
        window = {
          titlebar = false;
          border = 1;
          hideEdgeBorders = "smart";
          commands = [
            {
              command = "tearing enable";
              criteria = {
                class = "cs2";
              };
            }
          ];
        };
        floating = {
          titlebar = false;
          border = 1;
        };
        gaps = {
          inner = 15;
          smartGaps = true;
        };
        focus = {
          followMouse = false;
          wrapping = "no";
        };
        workspaceAutoBackAndForth = true;
        defaultWorkspace = "workspace number 1";
        keybindings =
          let
            inherit modifier;
          in
          lib.mkOptionDefault {
            "${modifier}+p" = "exec ${pkgs.swaylock}/bin/swaylock";
            "${modifier}+shift+p" = "output 'DP-1' toggle; output 'DP-3' toggle";
            "${modifier}+shift+u" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "${modifier}+shift+y" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+shift+i" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "shift+XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+m" = "exec ${(pkgs.writeShellScript "toggle-mic-monitor" ''
              MODULE_ID=$(pactl list modules short | grep "module-loopback" | awk '{print $1}')
              if [ -n "$MODULE_ID" ]; then
                  pactl unload-module "$MODULE_ID"
                  notify-send "Transparency Mode" "OFF"
              else
                  pactl load-module module-loopback latency_msec=2
                  notify-send "Transparency Mode" "ON"
              fi
            '')}";

            "${modifier}+space" = "exec ${pkgs.mako}/bin/makoctl dismiss";
            "${modifier}+c" = "exec ${pkgs.mako}/bin/makoctl invoke default";
            "${modifier}+z" = "exec ${pkgs.mako}/bin/makoctl restore";
            "${modifier}+shift+t" = "exec ${(pkgs.writeShellScript "trim-yt-url" ''
              url=$(${pkgs.wl-clipboard}/bin/wl-paste --no-newline)
              if echo "$url" | ${pkgs.gnugrep}/bin/grep -qE 'https?://((www|music)\.)?youtube\.com/|youtu\.be/)'; then
                echo "$url" | ${pkgs.gnused}/bin/sed 's/&.*//' | ${pkgs.wl-clipboard}/bin/wl-copy
              fi
            '')}";
            "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
              focused=$(${pkgs.sway}/bin/swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim -o "$focused" - < "$temp_file" | ${pkgs.wl-clipboard}/bin/wl-copy
              ${pkgs.grim}/bin/grim -o "$focused" $HOME/Pictures/Screenshots/screenshot-$(date +%Y%m%d%H%M%S).png
            '')}";
            "${modifier}+x" = "exec ${(pkgs.writeShellScript "screenshot-select" ''
              focused=$(${pkgs.sway}/bin/swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim -o "$focused" "$temp_file"
              ${pkgs.imv}/bin/imv -f "$temp_file" &
              imv_pid=$!
              sleep 0.1
              region=$(${pkgs.slurp}/bin/slurp -o "$focused")
              if [ -n "$region" ]; then
                  ${pkgs.grim}/bin/grim -g "$region" - < "$temp_file" | ${pkgs.wl-clipboard}/bin/wl-copy
                  ${pkgs.grim}/bin/grim -g "$region" $HOME/Pictures/Screenshots/screenshot-$(date +%Y%m%d%H%M%S).png
              fi
              kill $imv_pid
              rm "$temp_file"
            '')}";
            "${modifier}+n" = "exec '${pkgs.sway}/bin/swaymsg \"bar mode toggle\"'";
            "XF86AudioRaiseVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+";
            "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-";
            "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +1%";
            "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
            "${modifier}+i" = "inhibit_idle toggle";
            "${modifier}+Shift+e" = "exec ${pkgs.wlogout}/bin/wlogout -b 2";
          };
        assigns = { };
      };
      extraConfig =
        let
          inherit modifier;
        in
        ''
          for_window [title="^mpv-pip$"] floating enable, sticky enable

          bindsym --whole-window {
            ${modifier}+Shift+button4 exec "${pkgs.brightnessctl}/bin/brightnessctl set +1%"
            ${modifier}+Shift+button5 exec "${pkgs.brightnessctl}/bin/brightnessctl set 1%-"
            ${modifier}+button4 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%+"
            ${modifier}+button5 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%-"
          }
          mouse_warping none
          exec '${pkgs.mako}/bin/mako'
          exec '${pkgs.wljoywake}/bin/wljoywake'
        '';
    };
}
