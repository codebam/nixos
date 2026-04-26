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

  systemd.user.services.pipewire.environment = {
    SPA_PLUGIN_DIR = lib.mkForce "${pkgs.pipewire}/lib/spa-0.2";
    LADSPA_PATH = lib.mkForce "${pkgs.lsp-plugins}/lib/ladspa:${pkgs.ladspaPlugins}/lib/ladspa";
    LV2_PATH = lib.mkForce "/run/current-system/sw/lib/lv2";
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
      "99-chromium-stereo" = {
        "node.rules" = [
          {
            matches = [
              { "application.name" = "~[Cc]hromium*"; }
            ];
            actions = {
              "update-props" = {
                "audio.channels" = 2;
                "audio.position" = "[ FL, FR ]";
              };
            };
          }
        ];
      };
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
        pipewire-pulse = {
          "99-routing" = {
            "pulse.rules" = [
              {
                matches = [ { "application.name" = "~[Cc]hromium*"; } ];
                actions = {
                  "update-props" = {
                    "node.target" = "chromium_input";
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
        pipewire = {
          "99-routing" = {
            "node.rules" = [
              {
                matches = [
                  {
                    "node.name" = "SDL Application";
                    "media.role" = "Game";
                  }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "cs2_router";
                    "target.object" = "cs2_router";
                    "volume" = 2.0;
                  };
                };
              }
            ];
          };
          "99-cs2-ducking-system" = {
            "context.modules" = [
              # CS2 sink — direct to DAC
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "CS2 Router";
                  "capture.props" = {
                    "node.name" = "cs2_router";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [
                      "FL"
                      "FR"
                    ];
                  };
                  "playback.props" = {
                    "node.name" = "cs2_dac_out";
                    "target.object" = "alsa_output.usb-QTIL_Qudelix-5K_USB_DAC_ABCDEF0123456789-00.analog-stereo";
                  };
                };
              }
              # Combine-stream sink: merges Chromium (FL/FR) and CS2 monitor (RL/RR)
              # into a single 4-channel stream feeding the filter-chain
              {
                name = "libpipewire-module-combine-stream";
                args = {
                  "node.name" = "chromium_input";
                  "node.description" = "Chromium Input";
                  "combine.mode" = "sink";
                  "audio.channels" = 4;
                  "audio.position" = [
                    "FL"
                    "FR"
                    "RL"
                    "RR"
                  ];
                  "stream.props" = {
                    "node.passive" = false;
                    "target.object" = "ducking_sink";
                  };
                  "stream.rules" = [
                    {
                      matches = [ { "application.name" = "~[Cc]hromium*"; } ];
                      actions = {
                        "create-stream" = {
                          "audio.position" = [
                            "FL"
                            "FR"
                          ];
                          "channelmix.upmix" = false;
                        };
                      };
                    }
                    {
                      matches = [ { "node.name" = "cs2_router"; } ];
                      actions = {
                        "create-stream" = {
                          "audio.position" = [
                            "RL"
                            "RR"
                          ];
                          "channelmix.upmix" = false;
                        };
                      };
                    }
                  ];
                };
              }
              # Filter-chain ducker
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
                          "scr" = 2;
                          "sct" = 0;
                          "scm" = 0;
                          "shpm" = 1.0;
                          "al" = 0.1;
                          "at" = 5.0;
                          "rt" = 500.0;
                          "cr" = 10.0;
                          "kn" = 0.5;
                          "mk" = 1.0;
                          "cdr" = 0.0;
                          "cwt" = 1.0;
                        };
                      }
                    ];
                    inputs = [
                      "ducker:in_l"
                      "ducker:in_r"
                      "ducker:sc_l"
                      "ducker:sc_r"
                    ];
                    outputs = [
                      "ducker:out_l"
                      "ducker:out_r"
                    ];
                  };
                  "capture.props" = {
                    "node.name" = "ducking_sink";
                    "media.class" = "Audio/Sink";
                    "audio.channels" = 4;
                    "audio.position" = [
                      "FL"
                      "FR"
                      "RL"
                      "RR"
                    ];
                    "channelmix.upmix" = false;
                  };
                  "playback.props" = {
                    "node.name" = "ducking_output";
                    "node.passive" = false;
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
