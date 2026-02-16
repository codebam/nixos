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
                  "node.description" = "Letshuoer S12 Pro (31-Band GEQ)";
                  "media.name" = "Letshuoer S12 Pro (31-Band GEQ)";
                  "filter.graph" = {
                    "nodes" = [
                      {
                        "type" = "builtin";
                        "name" = "preamp";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 0.0; "Gain" = -1.5; "Q" = 1.0; };
                      }
                      { "type" = "builtin"; "name" = "band_20";    "label" = "bq_peaking"; "control" = { "Freq" = 20.0;    "Gain" = -0.03; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_25";    "label" = "bq_peaking"; "control" = { "Freq" = 25.0;    "Gain" = -0.18; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_31";    "label" = "bq_peaking"; "control" = { "Freq" = 31.5;    "Gain" = -0.59; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_40";    "label" = "bq_peaking"; "control" = { "Freq" = 40.0;    "Gain" = -1.11; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_50";    "label" = "bq_peaking"; "control" = { "Freq" = 50.0;    "Gain" = -1.57; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_63";    "label" = "bq_peaking"; "control" = { "Freq" = 63.0;    "Gain" = -2.02; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_80";    "label" = "bq_peaking"; "control" = { "Freq" = 80.0;    "Gain" = -2.46; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_100";   "label" = "bq_peaking"; "control" = { "Freq" = 100.0;   "Gain" = -2.82; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_125";   "label" = "bq_peaking"; "control" = { "Freq" = 125.0;   "Gain" = -3.10; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_160";   "label" = "bq_peaking"; "control" = { "Freq" = 160.0;   "Gain" = -3.31; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_200";   "label" = "bq_peaking"; "control" = { "Freq" = 200.0;   "Gain" = -3.47; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_250";   "label" = "bq_peaking"; "control" = { "Freq" = 250.0;   "Gain" = -3.44; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_315";   "label" = "bq_peaking"; "control" = { "Freq" = 315.0;   "Gain" = -2.95; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_400";   "label" = "bq_peaking"; "control" = { "Freq" = 400.0;   "Gain" = -2.37; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_500";   "label" = "bq_peaking"; "control" = { "Freq" = 500.0;   "Gain" = -1.91; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_630";   "label" = "bq_peaking"; "control" = { "Freq" = 630.0;   "Gain" = -1.41; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_800";   "label" = "bq_peaking"; "control" = { "Freq" = 800.0;   "Gain" = -1.10; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_1000";  "label" = "bq_peaking"; "control" = { "Freq" = 1000.0;  "Gain" = -1.44; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_1250";  "label" = "bq_peaking"; "control" = { "Freq" = 1250.0;  "Gain" = -1.73; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_1600";  "label" = "bq_peaking"; "control" = { "Freq" = 1600.0;  "Gain" = -1.98; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_2000";  "label" = "bq_peaking"; "control" = { "Freq" = 2000.0;  "Gain" = -2.23; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_2500";  "label" = "bq_peaking"; "control" = { "Freq" = 2500.0;  "Gain" = -2.48; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_3150";  "label" = "bq_peaking"; "control" = { "Freq" = 3150.0;  "Gain" = -2.40; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_4000";  "label" = "bq_peaking"; "control" = { "Freq" = 4000.0;  "Gain" = -1.56; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_5000";  "label" = "bq_peaking"; "control" = { "Freq" = 5000.0;  "Gain" = -3.54; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_6300";  "label" = "bq_peaking"; "control" = { "Freq" = 6300.0;  "Gain" = -7.05; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_8000";  "label" = "bq_peaking"; "control" = { "Freq" = 8000.0;  "Gain" = -3.78; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_10000"; "label" = "bq_peaking"; "control" = { "Freq" = 10000.0; "Gain" = -1.52; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_12500"; "label" = "bq_peaking"; "control" = { "Freq" = 12500.0; "Gain" = -4.52; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_16000"; "label" = "bq_peaking"; "control" = { "Freq" = 16000.0; "Gain" = -1.00; "Q" = 4.3; }; }
                      { "type" = "builtin"; "name" = "band_20000"; "label" = "bq_peaking"; "control" = { "Freq" = 20000.0; "Gain" = 0.01;  "Q" = 4.3; }; }
                    ];
                    "links" = [
                      { "output" = "preamp:Out"; "input" = "band_20:In"; }
                      { "output" = "band_20:Out"; "input" = "band_25:In"; }
                      { "output" = "band_25:Out"; "input" = "band_31:In"; }
                      { "output" = "band_31:Out"; "input" = "band_40:In"; }
                      { "output" = "band_40:Out"; "input" = "band_50:In"; }
                      { "output" = "band_50:Out"; "input" = "band_63:In"; }
                      { "output" = "band_63:Out"; "input" = "band_80:In"; }
                      { "output" = "band_80:Out"; "input" = "band_100:In"; }
                      { "output" = "band_100:Out"; "input" = "band_125:In"; }
                      { "output" = "band_125:Out"; "input" = "band_160:In"; }
                      { "output" = "band_160:Out"; "input" = "band_200:In"; }
                      { "output" = "band_200:Out"; "input" = "band_250:In"; }
                      { "output" = "band_250:Out"; "input" = "band_315:In"; }
                      { "output" = "band_315:Out"; "input" = "band_400:In"; }
                      { "output" = "band_400:Out"; "input" = "band_500:In"; }
                      { "output" = "band_500:Out"; "input" = "band_630:In"; }
                      { "output" = "band_630:Out"; "input" = "band_800:In"; }
                      { "output" = "band_800:Out"; "input" = "band_1000:In"; }
                      { "output" = "band_1000:Out"; "input" = "band_1250:In"; }
                      { "output" = "band_1250:Out"; "input" = "band_1600:In"; }
                      { "output" = "band_1600:Out"; "input" = "band_2000:In"; }
                      { "output" = "band_2000:Out"; "input" = "band_2500:In"; }
                      { "output" = "band_2500:Out"; "input" = "band_3150:In"; }
                      { "output" = "band_3150:Out"; "input" = "band_4000:In"; }
                      { "output" = "band_4000:Out"; "input" = "band_5000:In"; }
                      { "output" = "band_5000:Out"; "input" = "band_6300:In"; }
                      { "output" = "band_6300:Out"; "input" = "band_8000:In"; }
                      { "output" = "band_8000:Out"; "input" = "band_10000:In"; }
                      { "output" = "band_10000:Out"; "input" = "band_12500:In"; }
                      { "output" = "band_12500:Out"; "input" = "band_16000:In"; }
                      { "output" = "band_16000:Out"; "input" = "band_20000:In"; }
                    ];
                    "inputs"  = [ "preamp:In" ];
                    "outputs" = [ "band_20000:Out" ];
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
