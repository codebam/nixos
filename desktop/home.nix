{
  inputs,
  pkgs,
  lib,
  ...
}:

let
  # Best-effort desktop notification for the marker written by
  # desktop/configuration/auto-upgrade.nix. Runs from a user timer rather than
  # a PathExists= unit: systemd restarts a path-triggered service immediately
  # whenever it exits while the path still exists (systemd.path(5)), which
  # would repeat the notification. The timer instead compares the marker body
  # with a per-session state file, so each still-pending marker is announced
  # once and a failed send is retried on the next tick.
  rebootNotify = pkgs.writeShellApplication {
    name = "nixos-reboot-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      marker=/run/nixos-upgrade/reboot-required
      runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      state="$runtime/nixos-reboot-notified"

      if [ ! -r "$marker" ]; then
        rm -f "$state"
        exit 0
      fi

      body="$(cat "$marker" 2>/dev/null || true)"
      [ -n "$body" ] || body="Kernel or firmware updates were installed. Reboot to use them."

      # Already announced this exact marker. A rewritten marker with the same
      # text keeps the same state, while a send that failed (Viewport not on
      # the bus yet) leaves the state unwritten and is retried next tick.
      if [ -r "$state" ] && [ "$(cat "$state" 2>/dev/null || true)" = "$body" ]; then
        exit 0
      fi

      notification_args=(
        --app-name "NixOS Upgrade"
        --urgency=critical
        --expire-time=0
        --icon=system-reboot
        "Reboot required"
      )

      # A failed send writes no state, so the next tick retries it.
      if notify-send "''${notification_args[@]}" "$body"; then
        printf '%s\n' "$body" > "$state"
      fi
    '';
  };
in
{

  programs.voxtype.package = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.vulkan;

  home = {
    # android-studio is not here: it is 3.5 GB plus a 470 MB JDK 17 that
    # nothing else in this closure wants, for a tool used a few times a year.
    # `nix shell nixpkgs#android-studio` when it is actually needed.
    packages = with pkgs; [
      # SigmaShake's desktop app and CLI stay packaged
      # (pkgs/sigmashake-desktop.nix, pkgs/ssg.nix) but are not on PATH:
      # dsh's built-in sandbox and the OpenSandbox containers are the working
      # boundaries now. Re-add either here to use it.
      # Launches the vendor AppImage kept at ~/Downloads (pkgs/polariumcode).
      polariumcode
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
        # tearing enable for class "cs2" comes from home/sway.nix.
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
    podman = {
      enable = true;
    };
  };

  systemd.user = {
    # The system-side counterpoint lives in desktop/configuration/auto-upgrade.nix.
    # OnStartupSec covers the marker that was already there when the user
    # manager started (the overnight-update case); OnUnitActiveSec keeps
    # checking while logged in.
    timers.nixos-reboot-required = {
      Unit = {
        Description = "Check for a NixOS kernel or firmware reboot marker";
      };
      Timer = {
        OnStartupSec = "30s";
        OnUnitActiveSec = "1min";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

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
          ExecStart = "${lib.getExe pkgs.openrgb} -p default.orp";
        };
        Install = {
          WantedBy = [
            "default.target"
          ];
        };
      };

      nixos-reboot-required = {
        Unit = {
          Description = "Notify that a NixOS update is waiting for a reboot";
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe rebootNotify;
        };
      };
    };
  };

  programs = {
    git = {
      signing = {
        key = "0271B12CCF0A185B01EB25FA4B1C30CAAB93976B";
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
        on-click = "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
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
        on-click = "${lib.getExe pkgs.playerctl} play-pause";
        on-click-middle = "${lib.getExe pkgs.playerctl} previous";
        on-click-right = "${lib.getExe pkgs.playerctl} next";
        on-scroll-up = "${lib.getExe pkgs.playerctl} position 10+";
        on-scroll-down = "${lib.getExe pkgs.playerctl} position 10-";
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
        exec = lib.getExe (
          pkgs.writeShellApplication {
            name = "amd-gpu-status";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              gpu=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n1)
              vram_used=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -n1)
              vram_total=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -n1)
              if [ -n "$gpu" ] && [ -n "$vram_used" ] && [ -n "$vram_total" ] && [ "$vram_total" -gt 0 ]; then
                vram_pct=$(( vram_used * 100 / vram_total ))
                echo "󰢮 ''${gpu}% (''${vram_pct}%)"
              fi
            '';
          }
        );
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
    bindsym --whole-window button9 exec "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SOURCE@ 0"
    bindsym --whole-window --release button9 exec "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SOURCE@ 1"
    exec "${lib.getExe' pkgs.wireplumber "wpctl"} set-mute @DEFAULT_AUDIO_SOURCE@ 1"
  '';
}
