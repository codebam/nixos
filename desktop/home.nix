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
      (writeShellScriptBin "toggle-cs2-audio" ''
        #!/usr/bin/env bash
    
        # dependencies
        PATH=${lib.makeBinPath [ pkgs.jq pkgs.pipewire pkgs.wireplumber ]}:$PATH

        # --- CONFIGURATION ---
        # The Description of your EQ (Must match your nix config exactly)
        EQ_DESC="Simgot SuperMix 4 (CS2 Comp)"
        # The Node Name of your FiiO (Must match 'pw-dump' output)
        DAC_NAME="alsa_output.usb-FiiO_FiiO_KA3_FiiO_KA3-00.analog-stereo"

        # --- GET IDs ---
        # We still need the IDs to execute the switch command
        DAC_ID=$(pw-dump | jq -r --arg name "$DAC_NAME" '.[] | select(.info.props."node.name" == $name) | .id')
        EQ_ID=$(pw-dump | jq -r --arg desc "$EQ_DESC" '.[] | select(.info.props."node.description" == $desc) | .id')

        # --- SAFETY CHECKS ---
        if [ -z "$DAC_ID" ] || [ "$DAC_ID" == "null" ]; then
            notify-send -u critical "Audio Error" "FiiO KA3 not found!"
            exit 1
        fi
        if [ -z "$EQ_ID" ] || [ "$EQ_ID" == "null" ]; then
            notify-send -u critical "Audio Error" "CS2 Profile not found!"
            exit 1
        fi

        # --- TOGGLE LOGIC (FIXED) ---
        # Check if the current default sink's description contains our EQ name
        if wpctl inspect @DEFAULT_AUDIO_SINK@ | grep -q "$EQ_DESC"; then
            # CASE: EQ is currently Active -> Switch to FiiO (Stock)
            wpctl set-default "$DAC_ID"
            notify-send -u low -t 2000 "Audio: Music Mode" "Switched to FiiO KA3 (Stock)"
        else
            # CASE: EQ is NOT Active -> Switch to EQ (CS2)
            wpctl set-default "$EQ_ID"
            notify-send -u low -t 2000 "Audio: CS2 Mode" "Switched to SuperMix 4 (EQ)"
        fi
      '')
    ];
  };

  wayland.windowManager.sway.config = {
      output = {
      "*" = {
        mode = "2560x1440@239.760Hz";
        adaptive_sync = "on";
        subpixel = "rgb";
        render_bit_depth = "8";
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
        criteria = { class = "cs2"; };
      }
      {
        command = "border none";
        criteria = { class = "cs2"; };
      }
      {
        command = "max_render_time off";
        criteria = { class = "cs2"; };
      }
      {
        command = "border none";
        criteria = { app_id = "cs2"; };
      }
      {
        command = "floating disable";
        criteria = { app_id = "cs2"; };
      }
      {
        command = "inhibit_idle focus";
        criteria = { app_id = "cs2"; };
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
            # {
            #   alert = 10.0;
            #   block = "disk_space";
            #   info_type = "available";
            #   interval = 60;
            #   path = "/backup";
            #   warning = 20.0;
            # }
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
