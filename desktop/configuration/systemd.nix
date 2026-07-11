{
  pkgs,
  config,
  lib,
  ...
}:

{
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

  systemd = {
    # targets = {
    #   sleep = {
    #     enable = false;
    #     unitConfig.DefaultDependencies = "no";
    #   };
    #   suspend = {
    #     enable = false;
    #     unitConfig.DefaultDependencies = "no";
    #   };
    #   hibernate = {
    #     enable = false;
    #     unitConfig.DefaultDependencies = "no";
    #   };
    #   "hybrid-sleep" = {
    #     enable = false;
    #     unitConfig.DefaultDependencies = "no";
    #   };
    # };
    # user = {
    #   services = {
    #     xdg-desktop-portal-wlr = {
    #       serviceConfig = {
    #         ExecStart = [ "" "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr -l DEBUG" ];
    #       };
    #     };
    #   };
    # };
    timers = {
      nix-build-steamdeck = {
        enable = false;
        description = "Daily NixOS Build Timer for Steam Deck Configuration";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = 3600;
        };
      };
    };
    services = {
      wifi-performance = {
        description = "Disable Wi-Fi Power Save";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.iw}/bin/iw dev wlan0 set power_save off";
          RemainAfterExit = true;
        };
      };
      navidrome = {
        serviceConfig.ProtectHome = lib.mkForce "read-only";
      };
      wifi-reconnect = {
        enable = false;
        description = "Reconnect Wi-Fi if disconnected";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "root";
          Restart = "always";
          RestartSec = "10s";
        };
        path = [
          pkgs.networkmanager
          pkgs.coreutils
          pkgs.gnugrep
        ];
        script = ''
              while true
              do
                if [[ "$(nmcli -t -f STATE general)" != "connected" ]]; then
          				for i in {1..3}; do nmcli connection up "BeeNetwork-5GHz" && break || sleep 1; done
          				sleep 60
                  if [[ "$(nmcli -t -f STATE general)" != "connected" ]]; then
                    systemctl restart NetworkManager
                  fi
                fi
                sleep 10
              done
        '';
      };
      nix-build-steamdeck = {
        description = "NixOS Build Service for Steam Deck Configuration";
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/etc/nixos/cache/steamdeck";
          ExecStart = "/run/current-system/sw/bin/nix build /etc/nixos#nixosConfigurations.nixos-steamdeck.config.system.build.toplevel --print-build-logs";
        };
        path = [ pkgs.git ];
      };
      systemd-remount-fs = {
        enable = false;
      };
      applyGpuSettings = {
        description = "Apply GPU Overclocking and Power Limit Settings";
        after = [ "multi-user.target" ];
        wantedBy = [ "graphical.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # Dynamically find the AMD GPU card
          for card in /sys/class/drm/card[0-9]; do
            if [ -f "$card/device/vendor" ] && grep -q "0x1002" "$card/device/vendor"; then
              GPU_CARD="$card"
              break
            fi
          done

          if [ -z "$GPU_CARD" ]; then
            echo "AMD GPU not found!"
            exit 1
          fi

          echo "Using AMD GPU at $GPU_CARD"

          # Apply clock and voltage settings
          echo "s 0 500" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "s 1 3300" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "m 0 97" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "m 1 1300" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "vo -150" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "c" > "$GPU_CARD/device/pp_od_clk_voltage"

          # Dynamically find the hwmon directory and apply a safe power limit
          # Replace 350000000 (350W) with your verified safe max value
          for cap_file in "$GPU_CARD/device/hwmon"/hwmon*/power1_cap; do
            if [ -f "$cap_file" ]; then
              echo "334000000" > "$cap_file"
            fi
          done

          echo "high" > "$GPU_CARD/device/power_dpm_force_performance_level"
        '';
      };
      nixos-upgrade = {
        preStart = ''
          cd ${config.system.autoUpgrade.flake}
          /run/current-system/sw/bin/nix --experimental-features 'nix-command flakes' flake update
        '';
      };
    };
  };
}
