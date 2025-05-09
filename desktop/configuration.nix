{
  inputs,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "nixos-desktop";
  };

  environment.systemPackages = [ ];

  # boot.kernelPackages = pkgs.linuxPackages_latest;
  # boot.kernelPackages = inputs.master.legacyPackages.${pkgs.system}.linuxPackages_testing;
  boot.kernelPackages = pkgs.linuxPackages_testing;
  # boot.kernelPackages =
  #   let
  #     linux_next_pkg =
  #       { fetchgit, buildLinux, ... }@args:

  #       buildLinux (
  #         args
  #         // rec {
  #           version = "6.15.0";
  #           modDirVersion = "6.15.0-rc1-next-20250409";

  #           src = fetchgit {
  #             url = "git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git";
  #             rev = "next-20250409";
  #             sha256 = "sha256-2dLsYNwXWq9QnbKYnqmrojxt18U2OEg4x/4IOOJ9h54=";
  #             deepClone = false;
  #             leaveDotGit = false;
  #           };

  #           kernelPatches = [ ];

  #           extraMeta.branch = "next";

  #         }
  #         // (args.argsOverride or { })
  #       );
  #     linux_next = pkgs.callPackage linux_next_pkg { };
  #   in
  #   pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_next);

  systemd.services.applyGpuSettings = {
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
      echo "402000000" | tee /sys/class/drm/card1/device/hwmon/hwmon8/power1_cap
    '';
  };

  powerManagement.enable = true;

  # environment.variables = {
  #   RUSTICL_ENABLE = "1";
  # };
  # systemd.services.foldingathome.environment = {
  #   RUSTICL_ENABLE = "1";
  # };

  services = {
    xmrig = {
      enable = false;
      settings = {
        autosave = true;
        cpu = true;
        opencl = false;
        cuda = false;
        pools = [
          {
            url = "pool.supportxmr.com:443";
            user = "82ykgFnWJLe7waEdRNjMmfUGSLaMEYjdf4jvuAmrjhqkA2VXNZRvs913UQUX5zQr4c3PJvFbqhbBG4xGpqDLabuA8od54rs";
            keepalive = true;
            tls = true;
          }
        ];
      };
    };

    hardware.openrgb = {
      enable = true;
    };
    # foldingathome = {
    #   enable = true;
    #   user = "codebam";
    # };

    ollama = {
      enable = true;
      host = "0.0.0.0";
      acceleration = "rocm";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      };
    };
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
      extest = {
        enable = true;
      };
      gamescopeSession = {
        enable = true;
        args = [
          "--expose-wayland"
          "-e"
        ];
      };
    };
    gamemode = {
      enable = true;
    };
    gamescope = {
      enable = true;
    };
    corectrl = {
      enable = true;
      gpuOverclock.enable = true;
      gpuOverclock.ppfeaturemask = "0xffffffff";
    };
  };

  hardware = {
    fancontrol = {
      enable = false;
      config = ''
        # Configuration file generated by pwmconfig, changes will be lost
        INTERVAL=10
        DEVPATH=hwmon5=devices/pci0000:00/0000:00:03.1/0000:08:00.0/0000:09:00.0/0000:0a:00.0 hwmon6=devices/platform/nct6775.656
        DEVNAME=hwmon5=amdgpu hwmon6=nct6798
        FCTEMPS=hwmon6/pwm7=hwmon6/temp7_input hwmon6/pwm6=hwmon6/temp6_input hwmon6/pwm5=hwmon6/temp5_input hwmon6/pwm4=hwmon6/temp4_input hwmon6/pwm3=hwmon6/temp3_input hwmon6/pwm2=hwmon6/temp2_input hwmon6/pwm1=hwmon6/temp1_input
        FCFANS=hwmon6/pwm7=hwmon5/fan1_input hwmon6/pwm6=hwmon5/fan1_input hwmon6/pwm5=hwmon5/fan1_input hwmon6/pwm4=hwmon6/fan4_input+hwmon5/fan1_input hwmon6/pwm3=hwmon6/fan3_input+hwmon5/fan1_input hwmon6/pwm2=hwmon6/fan2_input+hwmon5/fan1_input hwmon6/pwm1=hwmon6/fan1_input
        MINTEMP=hwmon6/pwm7=20 hwmon6/pwm6=20 hwmon6/pwm5=20 hwmon6/pwm4=20 hwmon6/pwm3=20 hwmon6/pwm2=20 hwmon6/pwm1=20
        MAXTEMP=hwmon6/pwm7=60 hwmon6/pwm6=60 hwmon6/pwm5=60 hwmon6/pwm4=60 hwmon6/pwm3=60 hwmon6/pwm2=60 hwmon6/pwm1=60
        MINSTART=hwmon6/pwm7=150 hwmon6/pwm6=150 hwmon6/pwm5=150 hwmon6/pwm4=150 hwmon6/pwm3=150 hwmon6/pwm2=150 hwmon6/pwm1=150
        MINSTOP=hwmon6/pwm7=100 hwmon6/pwm6=100 hwmon6/pwm5=100 hwmon6/pwm4=100 hwmon6/pwm3=100 hwmon6/pwm2=100 hwmon6/pwm1=0
      '';
    };
    graphics = {
      enable32Bit = true;
      extraPackages = with pkgs; [ gamescope-wsi ];
    };
    # amdgpu.amdvlk = {
    #   enable = true;
    #   support32Bit.enable = true;
    # };
  };

  # nixpkgs.overlays = [
  #   (self: super: {
  #     linuxPackages_latest = super.linuxPackages_latest.extend (lpself: lpsuper: {
  #       rtl8814au = super.linuxPackages_latest.rtl8814au.overrideAttrs (oldAttrs: {
  #         version = "${config.boot.kernelPackages.kernel.version}-unstable-2024-09-17";
  #         src = pkgs.fetchFromGitHub {
  #           owner = "morrownr";
  #           repo = "8814au";
  #           rev = "d8208c83ecfd9b286f3ea45a7eb7d78d10560670";
  #           hash = "sha256-lKTxWpmC17ecKr9oBHgkyKumR0rvsZoBklq7TKjI6L4=";
  #         };
  #       });
  #     });
  #   })
  # ];

  nixpkgs.config.rocmSupport = true;
  nixpkgs.overlays = [
    (final: prev: {
      linuxPackages_xanmod_latest = inputs.xanmod.legacyPackages.${pkgs.system}.linuxPackages_xanmod_latest;
      # rocmPackages_6 = inputs.rocm.legacyPackages.${pkgs.system}.rocmPackages_6.gfx1100;
      # ollama = inputs.rocm.legacyPackages.${pkgs.system}.ollama;
      # ollama = inputs.ollama.legacyPackages.${pkgs.system}.ollama.overrideAttrs (oldAttrs: {
      #   doCheck = false;
      # });
    })
  ];

  # linuxPackages_testing = inputs.rc2.legacyPackages.${pkgs.system}.linuxPackages_testing;
  # linuxPackages_latest = inputs.linux-latest-update.legacyPackages.${pkgs.system}.linuxPackages_testing;
  # bcachefs-tools = inputs.bcachefs-fix.packages.${pkgs.system}.bcachefs;
  # rocmPackages = inputs.rocm.legacyPackages.${pkgs.system}.rocmPackages;

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
    ];

  system = {
    autoUpgrade = {
      enable = false;
      flake = "github:codebam/nixos#nixos-desktop";
      dates = "09:00";
    };
    stateVersion = "23.11";
  };
}
