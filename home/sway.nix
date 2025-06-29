{ pkgs
, lib
, config
, ...
}:

{
  wayland.windowManager.sway =
    let
      modifier = "Mod4";
    in
    {
      enable = true;
      systemd.enable = true;
      config = rec {
        inherit modifier;
        terminal = "${pkgs.foot}/bin/foot";
        menu = "${pkgs.wmenu}/bin/wmenu-run -f \"Fira Code NerdFont 11\" -i -N 1e1e2e -n 89b4fa -M 1e1e2e -m 89b4fa -S 89b4fa -s cdd6f4";
        seat = {
          "*" = {
            xcursor_theme = "Bibata-Modern-Ice";
          };
        };
        output = {
          "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
            mode = "3840x1600@143.998Hz";
            adaptive_sync = "off";
            subpixel = "none";
            render_bit_depth = "8";
            allow_tearing = "yes";
            max_render_time = "off";
            hdr = "on";
          };
          "eDP-1" = {
            scale = "1.5";
          };
        };
        input = {
          "*" = {
            events = "enabled";
          };
          "1133:49291:Logitech_G502_HERO_Gaming_Mouse" = {
            events = "enabled";
          };
          "13364:832:Keychron_Keychron_V4" = {
            events = "enabled";
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
          (lib.mkMerge [
            config.lib.stylix.sway.bar
            {
              statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
              mode = "dock";
              fonts = lib.mkForce {
                names = [ "Fira Code NerdFont" ];
                size = 11.0;
              };
              position = "top";
              hiddenState = "hide";
              trayOutput = "none";
              colors.background = lib.mkForce "#00000000";
            }
          ])
        ];
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
        focus = {
          followMouse = false;
          wrapping = "workspace";
        };
        workspaceAutoBackAndForth = true;
        defaultWorkspace = "workspace number 1";
        keybindings =
          let
            inherit modifier;
          in
          lib.mkOptionDefault {
            "${modifier}+p" = "exec ${pkgs.swaylock}/bin/swaylock";
            "${modifier}+shift+p" = "exec ${pkgs.swaylock}/bin/swaylock & systemctl suspend";
            "${modifier}+shift+u" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "${modifier}+shift+y" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+shift+i" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "shift+XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+space" = "exec ${pkgs.mako}/bin/makoctl dismiss";
            "${modifier}+c" = "exec ${pkgs.mako}/bin/makoctl invoke default";
            "${modifier}+z" = "exec ${pkgs.mako}/bin/makoctl restore";
            "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim - < "$temp_file" | ${pkgs.wl-clipboard}/bin/wl-copy
              ${pkgs.grim}/bin/grim $HOME/Pictures/Screenshots/screenshot-$(date +%Y%m%d%H%M%S).png
            '')}";
            "${modifier}+x" = "exec ${(pkgs.writeShellScript "screenshot-select" ''
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim "$temp_file"
              ${pkgs.imv}/bin/imv -f "$temp_file" &
              imv_pid=$!
              sleep 0.1
              region=$(${pkgs.slurp}/bin/slurp)
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
          };
        assigns = {
          "1" = [
            { app_id = "^org\.telegram\.desktop$"; }
            { app_id = "^discord$"; }
            { app_id = "^Element$"; }
          ];
          "2" = [
            { app_id = "^librewolf$"; }
          ];
          "4" = [
            { class = "^steam$"; }
          ];
          "5" = [{ app_id = "^com\.github\.th_ch\.youtube_music$"; }];
        };
      };
      extraConfig =
        let
          inherit modifier;
        in
        ''
          bindsym --whole-window {
            ${modifier}+Shift+button4 exec "${pkgs.brightnessctl}/bin/brightnessctl set +1%"
            ${modifier}+Shift+button5 exec "${pkgs.brightnessctl}/bin/brightnessctl set 1%-"
            ${modifier}+button4 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%+"
            ${modifier}+button5 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%-"
          }
          exec '${pkgs.mako}/bin/mako'
        '';
    };
}
