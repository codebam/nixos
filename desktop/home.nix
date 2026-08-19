{ pkgs, ... }:

{

  home = {
    # android-studio is not here: it is 3.5 GB plus a 470 MB JDK 17 that
    # nothing else in this closure wants, for a tool used a few times a year.
    # `nix shell nixpkgs#android-studio` when it is actually needed.
    packages = with pkgs; [
      bolt-launcher
      # Desktop app stays packaged (pkgs/sigmashake-desktop.nix) but is not
      # on PATH. Re-add `sigmashake-desktop` here to turn it back on.
      ssg
    ];
  };

  wayland.windowManager.sway.config = {
    output = {
      "*" = {
        mode = "2560x1440@239.760Hz";
        adaptive_sync = "on";
        subpixel = "rgb";
        render_bit_depth = "8";
        hdr = "off";
        allow_tearing = "yes";
      };
      "DP-1" = {
        position = "0 0";
      };
      "DP-3" = {
        position = "2560 0";
      };
    };
    workspaceOutputAssign = [
      {
        workspace = "1";
        output = "DP-1";
      }
      {
        workspace = "10";
        output = "DP-3";
      }
    ];
    window.commands = [
      {
        command = "tearing enable";
        criteria = {
          class = "cs2";
        };
      }
      {
        command = "border none";
        criteria = {
          class = "cs2";
        };
      }
      {
        command = "max_render_time off";
        criteria = {
          class = "cs2";
        };
      }
      {
        command = "border none";
        criteria = {
          app_id = "cs2";
        };
      }
      {
        command = "floating disable";
        criteria = {
          app_id = "cs2";
        };
      }
      {
        command = "inhibit_idle focus";
        criteria = {
          app_id = "cs2";
        };
      }
    ];
  };

  services = {
    swaync = {
      enable = false;
    };
    podman = {
      enable = true;
      containers = {
      };
    };
  };

  systemd = {
    user = {
      services = {
        # Login only. Resume is handled by the openrgb-resume system unit in
        # desktop/configuration/systemd.nix -- there is no user-manager
        # suspend.target to bind to from here.
        openrgb-apply = {
          Unit = {
            Description = "Apply OpenRGB settings on login";
            After = [
              "default.target"
            ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.openrgb}/bin/openrgb -p default.orp";
          };
          Install = {
            WantedBy = [
              "default.target"
            ];
          };
        };
      };
    };
  };

  programs = {
    git = {
      signing = {
        key = "0271B12CCF0A185B01EB25FA4B1C30CAAB93976B";
        signByDefault = true;
      };
    };

    waybar.settings.mainBar = {
      modules-center = [
        "mpris"
      ];
      modules-right = [
        "pulseaudio"
        "pulseaudio#source"
        "network"
        "disk"
        "disk#games"
        "memory"
        "custom/amd_gpu"
        "temperature"
        "cpu"
        "custom/load"
        "clock"
      ];

      "pulseaudio#source" = {
        format = " {format_source} ";
        format-source = " 󰍬 {volume}% ";
        format-source-muted = " 󰍭 muted ";
        on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      };

      "mpris" = {
        format = " {player_icon} {dynamic} ";
        format-paused = " {status_icon} <i>{dynamic}</i> ";
        player-icons = {
          default = "▶";
        };
        status-icons = {
          paused = "⏸";
        };
        dynamic-order = [
          "title"
          "artist"
        ];
        dynamic-len = 25;
        on-click = "${pkgs.playerctl}/bin/playerctl play-pause";
        on-click-middle = "${pkgs.playerctl}/bin/playerctl previous";
        on-click-right = "${pkgs.playerctl}/bin/playerctl next";
        on-scroll-up = "${pkgs.playerctl}/bin/playerctl position 10+";
        on-scroll-down = "${pkgs.playerctl}/bin/playerctl position 10-";
      };

      "network" = {
        format = "󰈀 {ifname}";
        format-wifi = "󰤨 {essid} {signalStrength}%";
        format-ethernet = "󰈀 Wired";
        format-linked = "󰈀 {ifname} (No IP)";
        format-disconnected = "󰤭 Disconnected";
        format-disabled = "󰤭 Disabled";
        tooltip-format = "{ifname} via {gwaddr} 󰈀";
      };

      "disk#games" = {
        path = "/games";
        interval = 60;
        format = " 󰋊 /games: {free} ";
      };

      "memory" = {
        interval = 5;
        format = " 󰍛 {percentage}% ({used:0.1f}GiB) ";
      };

      "custom/amd_gpu" = {
        exec = "${pkgs.writeShellScript "amd-gpu-status" ''
          gpu=$(${pkgs.coreutils}/bin/cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
          vram_used=$(${pkgs.coreutils}/bin/cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
          vram_total=$(${pkgs.coreutils}/bin/cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
          if [ -n "$gpu" ] && [ -n "$vram_used" ] && [ -n "$vram_total" ] && [ "$vram_total" -gt 0 ]; then
            vram_pct=$(( vram_used * 100 / vram_total ))
            echo "󰢮 ''${gpu}% (''${vram_pct}%)"
          fi
        ''}";
        interval = 2;
        format = " {} ";
      };

      "temperature" = {
        critical-threshold = 80;
        format = " 󰔏 {temperatureC}°C ";
      };

    };
  };

  wayland.windowManager.sway.extraConfig = ''
    # Push to talk
    bindsym --whole-window button9 exec "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0"
    bindsym --whole-window --release button9 exec "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1"
    exec "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1"
  '';
}
