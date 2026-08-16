{
  config,
  pkgs,
  lib,
  ...
}:

{
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

  # 5700X3D: 8 cores, SMT on, siblings paired as n / n+8. Excluding 6,7,14,15
  # hands two whole physical cores to the compositor and OBS while streaming
  # mode is on; builds keep the other six. max-jobs is `auto` (16) with
  # cores = 2 (modules/system/nix.nix), so a rebuild will happily fill every
  # thread it is allowed to see -- the point is that it can no longer see
  # these four.
  streamingMode = {
    buildCpus = "0-5,8-13";
    # 32G of the 64G stays out of the builders' reach, so a big link step
    # cannot evict the page cache the encoder is reading through.
    buildMemoryHigh = "32G";
  };

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

      # The openrgb-apply user unit in desktop/home.nix is WantedBy
      # default.target, so it runs at login and never again -- the RGB state is
      # lost across a suspend and nothing put it back, despite that unit's
      # description claiming "on login and resume".
      #
      # This is a system unit rather than a second user unit because systemd
      # has no per-user suspend.target to hang one off: `systemctl --user cat
      # suspend.target` finds nothing on 261. post-resume.target is the
      # system-side hook. User = "codebam" so `-p default.orp` resolves against
      # that account's OpenRGB config directory, which is where the profile
      # lives -- as root it would look in /root and silently apply nothing.
      openrgb-resume = {
        description = "Re-apply OpenRGB profile after resume";
        after = [ "post-resume.target" ];
        wantedBy = [ "post-resume.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "codebam";
          # USB RGB controllers are not always back on the bus the instant
          # post-resume.target is reached, and openrgb applies to whatever it
          # enumerates at start with no retry of its own.
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
          ExecStart = "${lib.getExe config.services.hardware.openrgb.package} -p default.orp";
        };
      };

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
