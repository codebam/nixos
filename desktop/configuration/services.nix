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
          "99-simgot-music-eq" = {
            "context.modules" = [
              {
                "name" = "libpipewire-module-filter-chain";
                "args" = {
                  "node.description" = "Simgot SuperMix 4 (Reference)";
                  "media.name" = "Simgot SuperMix 4 (Reference)";
                  "filter.graph" = {
                    "nodes" = [
                      # Preamp: Adjusted for safety (-2dB is usually sufficient for cuts)
                      {
                        "type" = "builtin";
                        "name" = "preamp";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 0.0; "Gain" = -2.0; "Q" = 1.0; };
                      }
                      # Band 1: Bass Reduction (Low Shelf @ 110Hz) 
                      # Stock SM4 has a ~10dB Harman bass shelf. We cut this to flatten the response.
                      {
                        "type" = "builtin";
                        "name" = "band_bass";
                        "label" = "bq_lowshelf";
                        "control" = { "Freq" = 110.0; "Gain" = -2.5; "Q" = 0.7; };
                      }
                      # Band 2: Lower-Mid Fill (Peak @ 250Hz) 
                      # Fixes the Harman "scoop" to restore natural note weight and vocal body.
                      {
                        "type" = "builtin";
                        "name" = "band_body";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 250.0; "Gain" = 1.5; "Q" = 1.0; };
                      }
                      # Band 3: Upper-Mid Correction (Peak @ 3000Hz) 
                      # Slight reduction of the ear-gain peak for a more neutral, less forward presentation.
                      {
                        "type" = "builtin";
                        "name" = "band_shout";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 3000.0; "Gain" = -1.5; "Q" = 1.4; };
                      }
                      # Band 4: Sibilance Control (Peak @ 6000Hz)
                      # Essential for SM4 to remove harshness on "S" and "T" sounds.
                      {
                        "type" = "builtin";
                        "name" = "band_sibilance";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 6000.0; "Gain" = -2.5; "Q" = 2.0; };
                      }
                      # Band 5: PZT Timbre Tame (High Shelf @ 11500Hz)
                      # Smooths out the artificial "zing" from the Piezo driver.
                      {
                        "type" = "builtin";
                        "name" = "band_air";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 11500.0; "Gain" = -3.0; "Q" = 0.7; };
                      }
                    ];
                    "links" = [
                      { "output" = "preamp:Out"; "input" = "band_bass:In"; }
                      { "output" = "band_bass:Out"; "input" = "band_body:In"; }
                      { "output" = "band_body:Out"; "input" = "band_shout:In"; }
                      { "output" = "band_shout:Out"; "input" = "band_sibilance:In"; }
                      { "output" = "band_sibilance:Out"; "input" = "band_air:In"; }
                    ];
                    "inputs"  = [ "preamp:In" ];
                    "outputs" = [ "band_air:Out" ];
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
          "99-simgot-cs2" = {
            "context.modules" = [
              {
                "name" = "libpipewire-module-filter-chain";
                "args" = {
                  "node.description" = "Simgot SuperMix 4 (CS2 Comp)";
                  "media.name" = "Simgot SuperMix 4 (CS2 Comp)";
                  "filter.graph" = {
                    "nodes" = [
                      # Preamp: Safety reduction
                      {
                        "type" = "builtin";
                        "name" = "preamp";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 0.0; "Gain" = -4.0; "Q" = 1.0; };
                      }
                      # Band 1: Low Shelf 125Hz -4.0dB (CUTS Explosion Rumble)
                      {
                        "type" = "builtin";
                        "name" = "band_1";
                        "label" = "bq_lowshelf";
                        "control" = { "Freq" = 125.0; "Gain" = -4.0; "Q" = 0.7; };
                      }
                      # Band 2: Peak 250Hz -2.0dB (Removes Mud)
                      {
                        "type" = "builtin";
                        "name" = "band_2";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 250.0; "Gain" = -2.0; "Q" = 1.0; };
                      }
                      # Band 3: Peak 2000Hz +2.0dB (BOOSTS Footsteps)
                      {
                        "type" = "builtin";
                        "name" = "band_3";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 2000.0; "Gain" = 2.0; "Q" = 1.4; };
                      }
                      # Band 4: Peak 4000Hz +2.5dB (BOOSTS Info/Reloads)
                      {
                        "type" = "builtin";
                        "name" = "band_4";
                        "label" = "bq_peaking";
                        "control" = { "Freq" = 4000.0; "Gain" = 2.5; "Q" = 1.4; };
                      }
                      # Band 5: High Shelf 10000Hz -1.5dB (Reduces Fatigue/Piezo Zing)
                      {
                        "type" = "builtin";
                        "name" = "band_5";
                        "label" = "bq_highshelf";
                        "control" = { "Freq" = 10000.0; "Gain" = -1.5; "Q" = 0.7; };
                      }
                    ];
                    "links" = [
                      { "output" = "preamp:Out"; "input" = "band_1:In"; }
                      { "output" = "band_1:Out"; "input" = "band_2:In"; }
                      { "output" = "band_2:Out"; "input" = "band_3:In"; }
                      { "output" = "band_3:Out"; "input" = "band_4:In"; }
                      { "output" = "band_4:Out"; "input" = "band_5:In"; }
                    ];
                    "inputs"  = [ "preamp:In" ];
                    "outputs" = [ "band_5:Out" ];
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
          "99-balance-correction" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "Simgot SuperMix 4 Balance Correction";
                  "media.name" = "Simgot SuperMix 4 Balance Correction";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "builtin";
                        name = "mix_L";
                        label = "mixer";
                        control = { "Gain 1" = 1.1885; }; # +1.5 dB Boost
                      }
                      {
                        type = "builtin";
                        name = "mix_R";
                        label = "mixer";
                        control = { "Gain 1" = 1.0; };    # 0 dB (Neutral)
                      }
                    ];
                    # Map Graph Inputs (FL/FR) to the specific mixer inputs
                    inputs = [ "mix_L:In 1" "mix_R:In 1" ];
                    outputs = [ "mix_L:Out" "mix_R:Out" ];
                  };
                  "capture.props" = {
                    "node.name" = "correction_input";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [ "FL" "FR" ];
                  };
                  "playback.props" = {
                    "node.name" = "correction_output";
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
