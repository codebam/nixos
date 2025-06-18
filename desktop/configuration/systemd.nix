{ pkgs, config, ... }:

{
  powerManagement.enable = true;

  systemd = {
    timers = {
      nix-build-steamdeck = {
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
      nix-build-steamdeck = {
        description = "NixOS Build Service for Steam Deck Configuration";
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/etc/nixos/steamdeck-cache";
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
          # echo "s 0 500" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          # echo "s 1 3150" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          # echo "m 0 97" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          # echo "m 1 1300" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
          echo "vo -50" | tee /sys/class/drm/card1/device/pp_od_clk_voltage
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
