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
      "51-bluez-codecs" = {
        "monitor.bluez.properties" = {
          # Omitting aptx and aptx_hd forces the fallback to ldac or sbc_xq.
          "bluez5.codecs" = [ "ldac" "aac" "sbc_xq" "sbc" ];
        };
      };
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
                  "node.description" = "Letshuoer S12 Pro (PEQ)";
                  "media.name" = "Letshuoer S12 Pro (PEQ)";
                  "filter.graph" = {
                    "nodes" = [
                      {
                        "type" = "builtin";
                        "name" = "preamp";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 0.0; "Gain" = -0.5; "Q" = 1.0; };
                      }
                      { "type" = "builtin"; "name" = "filter_1";  "label" = "bq_peaking"; "control" = { "Freq" = 60.0;    "Gain" = -7.0; "Q" = 0.2; }; }
                      { "type" = "builtin"; "name" = "filter_2";  "label" = "bq_peaking"; "control" = { "Freq" = 61.0;    "Gain" = 1.0;  "Q" = 0.4; }; }
                      { "type" = "builtin"; "name" = "filter_3";  "label" = "bq_peaking"; "control" = { "Freq" = 1000.0;  "Gain" = -1.0; "Q" = 1.3; }; }
                      { "type" = "builtin"; "name" = "filter_4";  "label" = "bq_peaking"; "control" = { "Freq" = 2000.0;  "Gain" = -5.0; "Q" = 1.0; }; }
                      { "type" = "builtin"; "name" = "filter_5";  "label" = "bq_peaking"; "control" = { "Freq" = 3300.0;  "Gain" = 5.0;  "Q" = 2.0; }; }
                      { "type" = "builtin"; "name" = "filter_6";  "label" = "bq_peaking"; "control" = { "Freq" = 7000.0;  "Gain" = -9.0; "Q" = 1.2; }; }
                      { "type" = "builtin"; "name" = "filter_7";  "label" = "bq_peaking"; "control" = { "Freq" = 17000.0; "Gain" = -9.0; "Q" = 0.6; }; }
                      { "type" = "builtin"; "name" = "filter_8";  "label" = "bq_peaking"; "control" = { "Freq" = 8600.0;  "Gain" = 3.0;  "Q" = 5.0; }; }
                      { "type" = "builtin"; "name" = "filter_9";  "label" = "bq_peaking"; "control" = { "Freq" = 150.0;   "Gain" = 0.0;  "Q" = 0.7; }; }
                      { "type" = "builtin"; "name" = "filter_10"; "label" = "bq_peaking"; "control" = { "Freq" = 10000.0; "Gain" = 0.0;  "Q" = 1.0; }; }
                    ];
                    "links" = [
                      { "output" = "preamp:Out";    "input" = "filter_1:In"; }
                      { "output" = "filter_1:Out";  "input" = "filter_2:In"; }
                      { "output" = "filter_2:Out";  "input" = "filter_3:In"; }
                      { "output" = "filter_3:Out";  "input" = "filter_4:In"; }
                      { "output" = "filter_4:Out";  "input" = "filter_5:In"; }
                      { "output" = "filter_5:Out";  "input" = "filter_6:In"; }
                      { "output" = "filter_6:Out";  "input" = "filter_7:In"; }
                      { "output" = "filter_7:Out";  "input" = "filter_8:In"; }
                      { "output" = "filter_8:Out";  "input" = "filter_9:In"; }
                      { "output" = "filter_9:Out";  "input" = "filter_10:In"; }
                    ];
                    "inputs"  = [ "preamp:In" ];
                    "outputs" = [ "filter_10:Out" ];
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
