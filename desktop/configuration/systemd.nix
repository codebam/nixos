{
  config,
  pkgs,
  lib,
  ...
}:

{
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

  systemd = {
    services = {
      # services.hardware.openrgb exposes a port but no host, and OpenRGB's
      # own default for --server-host is 0.0.0.0. The SDK server is
      # unauthenticated and tailscale0/virbr0 are trusted interfaces, so that
      # handed device control to the whole tailnet. Same flags the module
      # generates, plus the address it does not let us set.
      openrgb.serviceConfig.ExecStart = lib.mkForce (
        "${lib.getExe config.services.hardware.openrgb.package} --server "
        + "--server-host 127.0.0.1 "
        + "--server-port ${toString config.services.hardware.openrgb.server.port}"
      );

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
      # systemd-remount-fs is disabled in desktop-laptop/configuration/systemd.nix,
      # which both hosts that wipe / on a LUKS/bcachefs root share.
      applyGpuSettings = {
        enable = true;
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
          echo "s 1 3050" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "m 0 97" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "m 1 1275" > "$GPU_CARD/device/pp_od_clk_voltage"
          echo "vo -35" > "$GPU_CARD/device/pp_od_clk_voltage"
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
      # No nixos-upgrade override: system.autoUpgrade.enable is false, so the
      # preStart `nix flake update` that used to sit here never ran.
    };
  };
}
