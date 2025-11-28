{ pkgs, config, ... }:

{
  powerManagement.enable = true;

  systemd = {
    targets = {
      sleep = {
        enable = false;
        unitConfig.DefaultDependencies = "no";
      };
      suspend = {
        enable = false;
        unitConfig.DefaultDependencies = "no";
      };
      hibernate = {
        enable = false;
        unitConfig.DefaultDependencies = "no";
      };
      "hybrid-sleep" = {
        enable = false;
        unitConfig.DefaultDependencies = "no";
      };
    };
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
          echo "s 0 500" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "s 1 3150" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "m 0 97" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "m 1 1300" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "vo -110" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "c" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "402000000" | tee /sys/class/drm/card1/device/hwmon/hwmon7/power1_cap
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
