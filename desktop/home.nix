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
    packages = with pkgs; [
      bolt-launcher
      # disabled until they use modern openssl
      android-studio
      # vllm
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
    mako = {
      settings = {
        output = "DP-3";
      };
    };
    podman = {
      enable = true;
      containers = {
        # open-webui = {
        #   autoStart = true;
        #   autoUpdate = "registry";
        #   description = "open-webui container";
        #   image = "ghcr.io/open-webui/open-webui:main";
        #   ports = [
        #     "8080:8080"
        #   ];
        #   volumes = [
        #     "open-webui-data:/app/backend/data"
        #   ];
        #   environment = {
        #     ENV = "prod";
        #     OLLAMA_BASE_URL = "http://host.containers.internal:11434";
        #     SEARXNG_QUERY_URL = "http://host.containers.internal:8081/search?q=<query>";
        #   };
        #   extraConfig = {
        #     Service = {
        #       TimeoutStartSec = 1800;
        #     };
        #   };
        # };
      };
    };
  };

  systemd = {
    user = {
      services = {
        openrgb-apply = {
          Unit = {
            Description = "Apply OpenRGB settings on login and resume";
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

    i3status-rust = {
      bars = {
        default = {
          blocks = [
            {
              block = "focused_window";
              format = " $title.str(max_w:40) |";
            }
            {
              block = "sound";
              format = " $icon $volume ";
            }
            {
              block = "sound";
              device_kind = "source";
              format = " $icon $volume ";
            }
            {
              block = "music";
              format = " $icon {$combo.str(max_w:25,rot_interval:0.5) $prev $play $next |} ";
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
              format = " $icon {$ssid $signal_strength|Wired} ";
            }
            {
              block = "disk_space";
              path = "/";
              format = " $icon /: $available ";
              info_type = "available";
              interval = 60;
              warning = 20.0;
              alert = 10.0;
            }
            {
              block = "disk_space";
              path = "/games";
              format = " $icon /games: $available ";
              info_type = "available";
              interval = 60;
              warning = 20.0;
              alert = 10.0;
            }
            {
              block = "memory";
              format = " $icon $mem_used_percents% ($mem_used) ";
            }
            {
              block = "amd_gpu";
              format = " $icon $utilization% ($vram_used_percents%) ";
            }
            {
              block = "temperature";
              format = " $icon $max C ";
            }
            {
              block = "cpu";
              format = " $icon $utilization% ";
            }
            {
              block = "load";
              format = " $icon $1m ";
            }
            {
              block = "time";
              format = " $icon $timestamp.datetime(f:'%a %b %d, %R') ";
              interval = 60;
            }
          ];
        };
      };
    };
  };
}
