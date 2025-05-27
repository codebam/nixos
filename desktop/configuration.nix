{
  pkgs,
  config,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "nixos-desktop";
  };

  environment.systemPackages = [ ];

  boot = {
    kernelPackages = pkgs.linuxPackages_testing;
    initrd = {
      systemd = {
        services = {
          create-needed-for-boot-dirs = {
            after = [ "unlock-bcachefs--.service" "cleanup-root.service" ];
            serviceConfig.KeyringMode = "inherit";
          };
          cleanup-root = {
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
            serviceConfig.KeyringMode = "inherit";
            requiredBy = [ "initrd.target" ];
            after = [
              "unlock-bcachefs--.service"
              "local-fs-pre.target"
            ];
            before = [ "sysroot.mount" ];
            script = ''
              mkdir -p /bcachefs_tmp
              mount -t bcachefs /dev/disk/by-id/nvme-Sabrent_Rocket_Q_FC6207030D4501357285-part3 /bcachefs_tmp
              if [[ -e /bcachefs_tmp/@root ]]; then
                mkdir -p /bcachefs_tmp/old_roots
                timestamp=$(date --date="@$(stat -c %Y /bcachefs_tmp/@root)" "+%Y-%m-%-d_%H:%M:%S")
                mv /bcachefs_tmp/@root "/bcachefs_tmp/old_roots/$timestamp"
              fi

              delete_subvolume_recursively() {
                IFS=$'\n'
                for i in $(bcachefs subvolume list -o "$1" | cut -f 2- -d ' '); do
                  delete_subvolume_recursively "/bcachefs_tmp/$i"
                done
                bcachefs subvolume delete "$1"
              }

              for i in $(find /bcachefs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
                delete_subvolume_recursively "$i"
              done

              bcachefs subvolume create /bcachefs_tmp/@root
              umount /bcachefs_tmp
            '';
          };
        };
      };
    };
  };

  systemd.services = {
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
        echo "402000000" | tee /sys/class/drm/card1/device/hwmon/hwmon8/power1_cap
      '';
    };
    nixos-upgrade = {
      preStart = ''
        cd ${config.system.autoUpgrade.flake}
        /run/current-system/sw/bin/nix --experimental-features 'nix-command flakes' flake update
      '';
    };
  };

  powerManagement.enable = true;

  services = {
    nginx = {
      enable = true;
      virtualHosts = {
        "ai.seanbehan.ca" = {
          enableACME = true;
          addSSL = true;
          locations = {
            "/" = {
              proxyPass = "http://localhost:8080/";
            };
          };
        };
      };
    };
    pipewire = {
      configPackages = [
        (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-high-sample-rate.conf" ''
          context.properties = {
            default.clock.allowed-rates = [ 192000 384000 768000 ]
            default.clock.rate = 192000
          }
        '')
      ];
    };
    hardware.openrgb = {
      enable = true;
    };
    open-webui = {
      enable = true;
      port = 8080;
      environment = {
        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
        ENABLE_WEB_SEARCH = "True";
        WEB_SEARCH_ENGINE = "searxng";
        SEARXNG_QUERY_URL = "http://localhost:8081/search?q=<query>";
      };
    };
    searx = {
      enable = true;
      settings = {
        server = {
          port = 8081;
          secret_key = "codebam";
        };
        search = {
          autocomplete = "google";
          formats = [ "html" "json" ];
        };
      };
    };
    ollama = {
      enable = true;
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
    };
    gamescope = {
      enable = true;
    };
    gamemode = {
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
    };
  };

  nixpkgs.config.rocmSupport = true;
  nixpkgs.overlays = [
    (final: prev: {
    })
  ];

  system = {
    autoUpgrade = {
      enable = true;
      flake = "/etc/nixos";
      operation = "switch";
      dates = "daily";
      randomizedDelaySec = "10min";
      allowReboot = false;
    };
    stateVersion = "23.11";
  };
}
