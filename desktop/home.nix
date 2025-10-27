{ pkgs, ... }:

{
  age = {
    # identityPaths = [
    #   ./secrets/identities/yubikey-5c.txt
    #   ./secrets/identities/yubikey-5c-nfc.txt
    # ];
    # secrets.duckdns-token.file = ../secrets/duckdns-token.age;
  };

  home = {
    file.".config/lsfg-vk/conf.toml".text = ''
      version = 1
      [global]
      [[game]]
      exe = "decky-lsfg-vk"
      multiplier = 2
    '';
    packages = with pkgs; [
      (writeShellScriptBin "lsfg" ''
        export LSFG_PROCESS=decky-lsfg-vk
        exec "$@"
      '')
      bolt-launcher
    ];
  };

  services = {
    podman = {
      enable = true;
      containers = {
        open-webui = {
          autoStart = true;
          autoUpdate = "registry";
          description = "open-webui container";
          image = "ghcr.io/open-webui/open-webui:main";
          ports = [
            "8080:8080"
          ];
          volumes = [
            "open-webui-data:/app/backend/data"
          ];
          environment = {
            ENV = "prod";
            OLLAMA_BASE_URL = "http://host.containers.internal:11434";
            SEARXNG_QUERY_URL = "http://host.containers.internal:8081/search?q=<query>";
          };
          extraConfig = {
            Service = {
              TimeoutStartSec = 1800;
            };
          };
        };
      };
    };
  };

  # systemd = {
  #   user = {
  #     services = {
  #       openrgb-apply = {
  #         Unit = {
  #           Description = "Apply OpenRGB settings on login and resume";
  #           After = [
  #             "default.target"
  #           ];
  #         };
  #         Service = {
  #           Type = "oneshot";
  #           ExecStart = "${pkgs.openrgb}/bin/openrgb -p default.orp";
  #         };
  #         Install = {
  #           WantedBy = [
  #             "default.target"
  #           ];
  #         };
  #       };
  #     };
  #   };
  # };

  programs = {
    git = {
      signing = {
        key = "0271B12CCF0A185B01EB25FA4B1C30CAAB93976B";
        signByDefault = true;
      };
    };

    i3status-rust = {
      bars = {
        default = {
          blocks = [
            { block = "focused_window"; }
            { block = "sound"; }
            {
              block = "sound";
              device_kind = "source";
            }
            {
              block = "music";
              format = " $icon {$combo.str(max_w:30,rot_interval:0.5) $prev $play $next |} ";
              seek_step_secs = 10;
              click = [
                {
                  button = "forward";
                  action = "seek_forward";
                }
                {
                  button = "back";
                  action = "seek_backward";
                }
              ];
            }
            {
              block = "net";
              format = " $icon {$signal_strength $ssid|Wired connection} ";
            }
            {
              alert = 10.0;
              block = "disk_space";
              info_type = "available";
              interval = 60;
              path = "/";
              warning = 20.0;
            }
            {
              alert = 10.0;
              block = "disk_space";
              info_type = "available";
              interval = 60;
              path = "/games";
              warning = 20.0;
            }
            {
              alert = 10.0;
              block = "disk_space";
              info_type = "available";
              interval = 60;
              path = "/backup";
              warning = 20.0;
            }
            {
              block = "memory";
              format = "$icon $mem_used_percents ";
            }
            {
              block = "amd_gpu";
              format = " $icon $utilization $vram_used_percents ";
            }
            { block = "temperature"; }
            { block = "cpu"; }
            { block = "load"; }
            {
              block = "time";
              interval = 60;
            }
          ];
        };
      };
    };
  };
}
