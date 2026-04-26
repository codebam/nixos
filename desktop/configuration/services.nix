{
  pkgs,
  config,
  lib,
  ...
}:

{
  age.secrets.navidrome-lastfm = {
    file = ../../secrets/navidrome-lastfm.age;
    owner = "navidrome";
    group = "navidrome";
  };
  age.secrets.mopidy-subidy = {
    file = ../../secrets/mopidy-subidy.age;
    owner = "codebam";
    group = "users";
  };

  # systemd.user.services.pipewire.environment = lib.mkForce {
  #   SPA_PLUGIN_DIR = "${pkgs.pipewire}/lib/spa-0.2";
  #   LADSPA_PATH = "${pkgs.ladspaPlugins}/lib/ladspa";
  # };
  systemd.user.services.pipewire.environment = {
    LV2_PATH = lib.mkForce "/run/current-system/sw/lib/lv2:${pkgs.lsp-plugins}/lib/lv2";
  };

  systemd.services.mopidy = {
    environment = {
      GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" [
        pkgs.gst_all_1.gst-plugins-base
        pkgs.gst_all_1.gst-plugins-good
        pkgs.pipewire
      ];
      PIPEWIRE_RUNTIME_DIR = "/run/user/1000";
      PIPEWIRE_REMOTE = "pipewire-0";
    };
    serviceConfig = {
      BindReadOnlyPaths = [ "/run/user/1000" ];
      User = lib.mkForce "codebam";
      Group = lib.mkForce "users";
    };
  };

  services = {
    mopidy = {
      enable = true;
      extensionPackages = with pkgs; [
        mopidy-subidy
        mopidy-mpd
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        pipewire
      ];
      settings = {
        core = {
          restore_state = true;
        };
        audio = {
          output = "pipewiresink";
        };
        mpd = {
          enabled = true;
          hostname = "0.0.0.0";
          port = 6600;
        };
      };
      extraConfigFiles = [
        config.age.secrets.mopidy-subidy.path
      ];
    };
    lidarr = {
      enable = true;
      openFirewall = true;
      user = "codebam";
      group = "users";
    };
    prowlarr = {
      enable = true;
      openFirewall = true;
    };
    transmission = {
      enable = true;
      openFirewall = true;
      user = "codebam";
      settings = {
        download-dir = "/home/codebam/Downloads/Music/.downloads";
        incomplete-dir = "/home/codebam/Downloads/Music/.incomplete";
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist = "127.0.0.1";
        umask = 2;
      };
    };
    navidrome = {
      enable = true;
      environmentFile = config.age.secrets.navidrome-lastfm.path;
      settings = {
        MusicFolder = "/home/codebam/Downloads/Lidarr";
        BaseUrl = "https://codebam.tplinkdns.com";
        Address = "0.0.0.0";
        Port = 4533;
        ScanSchedule = "@every 1h";
        DefaultLanguage = "en";
        EnableExternalServices = true;
        LastFM.Enabled = false;
        EnableSharing = true;
      };
      openFirewall = true;
    };
    meilisearch = {
      enable = false;
      masterKeyFile = "/var/lib/meilisearch-master-key";
    };
    librechat = {
      enable = false;
      enableLocalDB = true;
      meilisearch.enable = false;
      env = {
        PORT = 3080;
        CREDS_KEY = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        CREDS_IV = "0123456789abcdef0123456789abcdef";
        JWT_SECRET = "secure-jwt-secret-here";
        JWT_REFRESH_SECRET = "secure-refresh-token-secret-here";
        MEILI_MASTER_KEY = "your-secret-string-here";
        OPENAI_API_KEY = "user_provided";
        ALLOW_REGISTRATION = "true";
        ALLOW_SOCIAL_REGISTRATION = "false";
      };
      settings = {
        version = "1.3.5";
        cache = true;
        endpoints = {
          custom = [
            {
              name = "vLLM Gemma";
              apiKey = "vllm";
              baseURL = "http://127.0.0.1:8000/v1";
              models = {
                default = [ "google/gemma-4-E4B-it" ];
                fetch = true;
              };
            }
          ];
        };
      };
    };
    v2ray = {
      enable = false;
      config = {
        inbounds = [
          {
            port = 10086;
            protocol = "vmess";
            settings = {
              clients = [
                {
                  id = "b831381d-6324-4d53-ad4f-8cda48b30811";
                }
              ];
            };
          }
        ];
        outbounds = [
          {
            protocol = "freedom";
          }
        ];
      };
    };
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts."codebam.tplinkdns.com" = {
        addSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:4533";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Protocol $scheme;
          '';
        };
      };
    };
    xray = {
      enable = false;
      settings = {
        domainStrategy = "UseIPv4";
        inbounds = [
          {
            listen = "0.0.0.0";
            port = 443;
            protocol = "vless";
            settings = {
              clients = [
                {
                  id = "19872fad-62ec-47b2-bc7a-4923ec9e18b4";
                  flow = "xtls-rprx-vision";
                }
              ];
              decryption = "none";
              fallbacks = [
                {
                  dest = "127.0.0.1:8080";
                  xver = 1;
                }
              ];
            };
            streamSettings = {
              network = "tcp";
              security = "reality";
              realitySettings = {
                show = false;
                dest = "www.bing.com:443";
                serverNames = [
                  "www.bing.com"
                  "www.microsoft.com"
                  "login.microsoftonline.com"
                  "www.office.com"
                  "www.apple.com"
                  "updates.cdn-apple.com"
                ];
                privateKey = "8JXPmRKIPSONGTeEHJ6DxFZHmdRdJdCI211puUKqoUw";
                shortIds = [ "6ba85179e30d4fc2" ];
              };
              tcpSettings = {
                header = {
                  type = "none";
                };
              };
            };
          }
        ];
        outbounds = [
          {
            protocol = "freedom";
            tag = "direct";
          }
        ];
        routing = {
          domainStrategy = "AsIs";
          rules = [
            {
              type = "field";
              outboundTag = "direct";
              ip = [
                "0.0.0.0/0"
                "::/0"
              ];
            }
          ];
        };
        dns = {
          servers = [
            "1.1.1.1"
            "8.8.8.8"
          ];
        };
      };
    };
    iodine = {
      server = {
        enable = false;
        passwordFile = "/etc/nixos/iodine-password.txt";
        domain = "codebam.tplinkdns.com";
        ip = "10.0.0.1";
        extraConfig = "-c";
      };
    };

    irqbalance = {
      enable = false;
    };

    timesyncd.enable = false;
    chrony = {
      enable = true;
      servers = [
        "time.cloudflare.com"
        "time.google.com"
      ];
      extraConfig = ''
        makestep 1.0 3
      '';
    };

    pipewire.wireplumber.extraConfig = {
      # "51-bluez-codecs" = {
      #   "monitor.bluez.properties" = {
      #     "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
      #     "bluez5.codecs" = [ "ldac" "aac" "sbc_xq" "sbc" ];
      #   };
      # };
      "10-disable-communication-role" = {
        "wireplumber.settings" = {
          "policy.role-priorities" = {
            "Communication" = 0; # Stops it from hijacking "headsets"
          };
        };
      };
      "10-disable-suspend" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "node.name" = "~alsa_output.*"; }
              { "node.name" = "~alsa_input.*"; }
            ];
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
        # 1. PulseAudio rules (Catches Chromium AND CS2's default SDL Pulse audio)
        pipewire-pulse = {
          "99-routing" = {
            "pulse.rules" = [
              {
                matches = [ { "application.name" = "~[Cc]hromium*"; } ];
                actions = {
                  "update-props" = {
                    "node.target" = "ducking_sink";
                  };
                };
              }
              {
                matches = [
                  { "application.name" = "~SDL Application*"; }
                  { "application.name" = "~cs2*"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "cs2_router";
                  };
                };
              }
            ];
          };
        };
        # 2. Native PipeWire rules (Catches CS2 if SDL_AUDIODRIVER=pipewire is set)
        pipewire = {
          "99-routing" = {
            "node.rules" = [
              {
                matches = [
                  { "node.name" = "~.*SDL Application.*"; }
                  { "client.name" = "~.*SDL Application.*"; }
                  { "application.process.binary" = "cs2"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "cs2_router";
                    "target.object" = "cs2_router"; # WirePlumber relies on target.object
                  };
                };
              }
            ];
          };
          "99-cs2-ducking-system" = {
            "context.modules" = [
              # ---------------------------------------------------------
              # 1. First Loopback: The Game Sink & Sidechain Trigger
              # ---------------------------------------------------------
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "CS2 Sidechain Trigger";
                  "capture.props" = {
                    "node.name" = "cs2_router"; # Creates the sink your game connects to
                    "media.class" = "Audio/Sink";
                    "audio.position" = [
                      "FL"
                      "FR"
                    ];
                  };
                  "playback.props" = {
                    "node.name" = "cs2_trigger_out";
                    "target.object" = "ducking_sink"; # Sends to compressor sidechain
                    "audio.position" = [
                      "AUX0"
                      "AUX1"
                    ];
                  };
                };
              }
              # ---------------------------------------------------------
              # 2. Second Loopback: Sends Game Audio to your Headphones
              # ---------------------------------------------------------
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "CS2 Audio Passthrough";
                  "capture.props" = {
                    "node.name" = "cs2_monitor_in";
                    "node.target" = "cs2_router"; # Listens to the sink we created above
                    "stream.capture.sink" = true; # Specifically captures its output
                  };
                  "playback.props" = {
                    "node.name" = "cs2_dac_out";
                    "target.object" = "alsa_output.usb-QTIL_Qudelix-5K_USB_DAC_ABCDEF0123456789-00.analog-stereo";
                  };
                };
              }
              # ---------------------------------------------------------
              # 3. The Ducking Sink: ONLY runs the compressor on Music
              # ---------------------------------------------------------
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "True Ducking Sink";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "lv2";
                        name = "ducker";
                        plugin = "http://lsp-plug.in/plugins/lv2/sc_compressor_stereo";
                        control = {
                          "enabled" = 1.0; # Force plugin on
                          "scs" = 1.0; # Sidechain source (1 = External / AUX ports)

                          # -- Ducking Parameters --
                          "cr" = 6.0; # Ratio (6 = 6:1 ratio. How intensely the music ducks)
                          "at" = 3.0; # Attack (ms. How fast the music drops)
                          "rt" = 300.0; # Release (ms. How fast the music fades back in)

                          # Attack Threshold ("al"): How loud CS2 needs to be to trigger ducking.
                          # Since this is Linear Math, here is a cheat sheet:
                          # 1.0   =   0 dB (Highest threshold, game has to be max volume)
                          # 0.25  = -12 dB
                          # 0.125 = -18 dB
                          # 0.063 = -24 dB (A good starting point)
                          # 0.031 = -30 dB (Highly sensitive, quiet gunshots will trigger it)
                          "al" = 0.063;
                        };
                      }
                    ];
                    "inputs" = [
                      "ducker:in_l" # Channel 0 (FL): Music
                      "ducker:in_r" # Channel 1 (FR): Music
                      "ducker:sc_l" # Channel 2 (AUX0): CS2 Trigger
                      "ducker:sc_r" # Channel 3 (AUX1): CS2 Trigger
                    ];
                    "outputs" = [
                      "ducker:out_l" # Compressed Music Out L
                      "ducker:out_r" # Compressed Music Out R
                    ];
                  };
                  "capture.props" = {
                    "node.name" = "ducking_sink";
                    "media.class" = "Audio/Sink";
                    "audio.channels" = 4;
                    "audio.position" = [
                      "FL"
                      "FR"
                      "AUX0"
                      "AUX1"
                    ];
                    "channelmix.upmix" = false;
                  };
                  "playback.props" = {
                    "node.name" = "ducking_output";
                    "node.passive" = false; # Prevents the graph from going to sleep
                    "target.object" = "alsa_output.usb-QTIL_Qudelix-5K_USB_DAC_ABCDEF0123456789-00.analog-stereo";
                  };
                };
              }
            ];
          };
          "92-low-latency" = {
            "context.properties" = {
              "default.clock.quantum" = 256;
              "default.clock.min-quantum" = 256;
              "default.clock.max-quantum" = 512;
            };
          };
          "10-high-sample-rates" = {
            "context.properties" = {
              "default.clock.allowed-rates" = [
                44100
                48000
                88200
                96000
              ];
              "default.clock.rate" = 44100;
            };
          };
          # "99-cs2-hype4-peq" = {
          #   "context.modules" = [
          #     {
          #       name = "libpipewire-module-filter-chain";
          #       args = {
          #         "node.description" = "Hype 4 MKII - CS2 Competitive";
          #         "media.name" = "Hype 4 MKII - CS2 Competitive";
          #         "filter.graph" = {
          #           nodes = [
          #             {
          #               type = "builtin";
          #               name = "preamp";
          #               label = "bq_highshelf";
          #               control = {
          #                 "Freq" = 0;
          #                 "Gain" = -4.0;
          #                 "Q" = 1.0;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band1";
          #               label = "bq_lowshelf";
          #               control = {
          #                 "Freq" = 150.0;
          #                 "Gain" = -7.0;
          #                 "Q" = 0.71;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band2";
          #               label = "bq_peaking";
          #               control = {
          #                 "Freq" = 400.0;
          #                 "Gain" = -2.0;
          #                 "Q" = 1.0;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band3";
          #               label = "bq_peaking";
          #               control = {
          #                 "Freq" = 2500.0;
          #                 "Gain" = 3.5;
          #                 "Q" = 1.5;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band4";
          #               label = "bq_peaking";
          #               control = {
          #                 "Freq" = 4000.0;
          #                 "Gain" = 3.0;
          #                 "Q" = 1.5;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band5";
          #               label = "bq_peaking";
          #               control = {
          #                 "Freq" = 8000.0;
          #                 "Gain" = -4.5;
          #                 "Q" = 2.0;
          #               };
          #             }
          #             {
          #               type = "builtin";
          #               name = "band6";
          #               label = "bq_highshelf";
          #               control = {
          #                 "Freq" = 12000.0;
          #                 "Gain" = -2.0;
          #                 "Q" = 0.71;
          #               };
          #             }
          #           ];
          #           links = [
          #             {
          #               output = "preamp:Out";
          #               input = "band1:In";
          #             }
          #             {
          #               output = "band1:Out";
          #               input = "band2:In";
          #             }
          #             {
          #               output = "band2:Out";
          #               input = "band3:In";
          #             }
          #             {
          #               output = "band3:Out";
          #               input = "band4:In";
          #             }
          #             {
          #               output = "band4:Out";
          #               input = "band5:In";
          #             }
          #             {
          #               output = "band5:Out";
          #               input = "band6:In";
          #             }
          #           ];
          #         };
          #         "capture.props" = {
          #           "node.name" = "cs2_optimized_peq_input";
          #           "media.class" = "Audio/Sink";
          #           "audio.channels" = 2;
          #           "audio.position" = [
          #             "FL"
          #             "FR"
          #           ];
          #         };
          #         "playback.props" = {
          #           "node.name" = "cs2_optimized_peq_output";
          #           "node.passive" = true;
          #           "target.object" = "alsa_output.usb-QTIL_Qudelix-5K_USB_DAC_ABCDEF0123456789-00.analog-stereo";
          #           "audio.channels" = 2;
          #           "audio.position" = [
          #             "FL"
          #             "FR"
          #           ];
          #         };
          #       };
          #     }
          #   ];
          # };
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
    noizdns = {
      enable = true;
      domain = "t.seanbehan.ca";
    };
  };
}
