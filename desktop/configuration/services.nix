{ pkgs
, config
, ...
}:

{
  services = {
    irqbalance = {
      enable = false;
    };

    timesyncd.enable = false;
    chrony = {
      enable = true;
      servers = [ "time.cloudflare.com" "time.google.com" ];
      extraConfig = ''
        makestep 1.0 3
      '';
    };
    
    pipewire.wireplumber.extraConfig = {
      "10-disable-suspend" = {
        "monitor.alsa.rules" = [
          {
            matches = [{ "node.name" = "~alsa_output.*"; } { "node.name" = "~alsa_input.*"; }];
            actions = {
              update-props = {
                "session.suspend-timeout-seconds" = 0;
              };
            };
          }
        ];
      };
    };
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
    sunshine = {
      enable = false;
      openFirewall = true;
      autoStart = true;
      settings = {
        output_name = "1";
        capture = "wlr";
        encoder = "vaapi";
        hevc_mode = "1";
      };
      applications = {
        apps = [
          {
            name = "Steam Big Picture";
            # cmd = "${pkgs.steam}/bin/steam -gamepadui";
            cmd = "${
              pkgs.writeShellApplication {
                name = "steam-on-ws10";
                runtimeInputs = [
                  pkgs.steam
                  pkgs.sway
                  pkgs.jq
                ];
                text = builtins.readFile ./scripts/sunshine-steam.sh;
              }
            }/bin/steam-on-ws10";
            auto-detach = "true";
          }
        ];
      };
    };
    ddclient = {
      enable = false;
      protocol = "duckdns";
      domains = [ "codebam" ];
      passwordFile = config.age.secrets.duckdns-token.path;
    };
    pipewire = {
      extraConfig = {
        pipewire = {
          "99-mono-downmix" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "FiiO KA3 Mono Downmix";
                  "media.name" = "FiiO KA3 Mono Downmix";
                  "filter.graph" = {
                    nodes = [
                      # 1. Mix Left+Right into a single Mono signal
                      {
                        type = "builtin";
                        name = "mix_mono";
                        label = "mixer";
                        control = { "Gain 1" = 0.5; "Gain 2" = 0.5; };
                      }
                      # 2. Create a dedicated node for the Left Output
                      {
                        type = "builtin";
                        name = "copy_L";
                        label = "copy";
                      }
                      # 3. Create a dedicated node for the Right Output
                      {
                        type = "builtin";
                        name = "copy_R";
                        label = "copy";
                      }
                    ];
                    # Map System Inputs -> Mixer Inputs
                    inputs = [ "mix_mono:In 1" "mix_mono:In 2" ];
          
                    # Map Copy Nodes -> System Outputs (Each output gets its own unique node)
                    outputs = [ "copy_L:Out" "copy_R:Out" ];
          
                    # Internal Wiring: Send the Mono Mix to BOTH Copy nodes
                    links = [
                      { output = "mix_mono:Out"; input = "copy_L:In"; }
                      { output = "mix_mono:Out"; input = "copy_R:In"; }
                    ];
                  };
                  "capture.props" = {
                    "node.name" = "mono_input";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [ "FL" "FR" ];
                  };
                  "playback.props" = {
                    "node.name" = "mono_output";
                    "node.passive" = true;
                    "audio.position" = [ "FL" "FR" ];
                    "node.target" = "alsa_output.usb-FiiO_FiiO_KA3_FiiO_KA3-00.analog-stereo";
                  };
                };
              }
            ];
          };
          "99-iem-safe" = {
            "context.modules" = [
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "IEM (Safe Mode)";
                  "capture.props" = {
                    "node.name" = "iem_safe_sink";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [ "FL" "FR" ];
                  };
                  "playback.props" = {
                    "node.name" = "iem_safe_out";
                    "node.target" = "alsa_output.usb-FiiO_FiiO_KA3_FiiO_KA3-00.analog-stereo";
                    "node.passive" = true;
                    "audio.position" = [ "FL" "FR" ];
                  };
                };
              }
            ];
          };
          "99-letshuoer-s12-pro-eq" = {
            "context.modules" = [
              {
                "name" = "libpipewire-module-filter-chain";
                "args" = {
                  "node.description" = "Letshuoer S12 Pro";
                  "media.name" = "Letshuoer S12 Pro";
                  "filter.graph" = {
                    "nodes" = [
                      {
                        "type" = "builtin";
                        "name" = "preamp";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 0.0; "Gain" = -1.5; "Q" = 1.0; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_1";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 21.0; "Gain" = 1.6; "Q" = 0.7; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_2";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 140.0; "Gain" = -1.5; "Q" = 0.5; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_3";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 250.0; "Gain" = -0.9; "Q" = 1.2; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_4";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 760.0; "Gain" = 0.8; "Q" = 1.7; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_5";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 4100.0; "Gain" = 3.5; "Q" = 2.0; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_6";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 5400.0; "Gain" = 4.0; "Q" = 2.0; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_7";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 6250.0; "Gain" = -11.0; "Q" = 1.0; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_8";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 9000.0; "Gain" = 5.5; "Q" = 1.5; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_9";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 10000.0; "Gain" = 1.7; "Q" = 0.707; };
                      }
                      {
                        "type" = "builtin";
                        "name" = "band_10";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 12500.0; "Gain" = -4.0; "Q" = 2.0; };
                      }
                    ];
                    "links" = [
                      { "output" = "preamp:Out"; "input" = "band_1:In"; }
                      { "output" = "band_1:Out"; "input" = "band_2:In"; }
                      { "output" = "band_2:Out"; "input" = "band_3:In"; }
                      { "output" = "band_3:Out"; "input" = "band_4:In"; }
                      { "output" = "band_4:Out"; "input" = "band_5:In"; }
                      { "output" = "band_5:Out"; "input" = "band_6:In"; }
                      { "output" = "band_6:Out"; "input" = "band_7:In"; }
                      { "output" = "band_7:Out"; "input" = "band_8:In"; }
                      { "output" = "band_8:Out"; "input" = "band_9:In"; }
                      { "output" = "band_9:Out"; "input" = "band_10:In"; }
                    ];
                    "inputs"  = [ "preamp:In" ];
                    "outputs" = [ "band_10:Out" ];
                  };
                  "audio.channels" = 2;
                  "audio.position" = [ "FL" "FR" ];
                  "capture.props" = {
                    "node.passive" = true;
                    "media.class" = "Audio/Sink";
                  };
                  "playback.props" = {
                    "node.passive" = false;
                    "target.object" = "alsa_output.usb-FiiO_FiiO_KA3_FiiO_KA3-00.analog-stereo";
                  };
                };
              }
            ];
          };
          "92-low-latency" = {
            "context.properties" = {
              "default.clock.quantum" = 128;
              "default.clock.min-quantum" = 64;
              "default.clock.max-quantum" = 512;
            };
          };
          "10-high-sample-rates" = {
            "context.properties" = {
              "default.clock.allowed-rates" = [ 44100 48000 192000 384000 768000 ];
              "default.clock.rate" = 48000;
            };
          };
        };
      };
    };
    hardware.openrgb = {
      enable = true;
    };
    open-webui = {
      enable = false;
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
      enable = false;
      environmentFile = config.age.secrets.searx-secret.path;
      settings = {
        server = {
          secret_key = "$SECRET_KEY";
          bind_address = "0.0.0.0";
          port = 8081;
        };
        search = {
          autocomplete = "google";
          formats = [
            "html"
            "json"
          ];
        };
      };
    };
    ollama = {
      enable = false;
      host = "0.0.0.0";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      };
    };
  };
}
