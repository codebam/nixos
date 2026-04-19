{ pkgs
, config
, lib
, ...
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
        Address = "0.0.0.0";
        Port = 4533;
        ScanSchedule = "@every 1h";
        DefaultLanguage = "en";
        EnableExternalServices = true;
        LastFM.Enabled = false;
      };
      openFirewall = true;
    };
    meilisearch = {
      enable = false;
      masterKeyFile = "/var/lib/meilisearch-master-key"; 
    };
    librechat = {
      enable = true;
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
      enable = true;
      config = {
        inbounds = [{
          port = 10086;
          protocol = "vmess";
          settings = {
            clients = [{
              id = "b831381d-6324-4d53-ad4f-8cda48b30811";
            }];
          };
        }];
        outbounds = [{
          protocol = "freedom";
        }];
      };
    };
    nginx = {
      enable = true;
      virtualHosts."codebam.tplinkdns.com" = {
        listen = [{
          addr = "127.0.0.1";
          port = 8080;
          proxyProtocol = true;
        }];
        root = "/var/www/xray-site";
        extraConfig = ''
          index index.html;
        '';
      };
    };
    xray = {
      enable = false;
      settings = {
        domainStrategy = "UseIPv4";
        inbounds = [{
          listen = "0.0.0.0";
          port = 443;
          protocol = "vless";
          settings = {
            clients = [{
              id = "19872fad-62ec-47b2-bc7a-4923ec9e18b4";
              flow = "xtls-rprx-vision";
            }];
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
        }];
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
              ip = [ "0.0.0.0/0" "::/0" ];
            }
          ];
        };
        dns = {
          servers = [ "1.1.1.1" "8.8.8.8" ];
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
      servers = [ "time.cloudflare.com" "time.google.com" ];
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
          "92-low-latency" = {
            "context.properties" = {
              "default.clock.quantum" = 128;
              "default.clock.min-quantum" = 64;
              "default.clock.max-quantum" = 512;
            };
          };
          "10-high-sample-rates" = {
            "context.properties" = {
              "default.clock.allowed-rates" = [ 44100 48000 ];
              "default.clock.rate" = 44100;
            };
          };
          "eq" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "EQ";
                  "media.name" = "EQ";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "builtin";
                        name = "preamp";
                        label = "bq_highshelf";
                        control = { "Freq" = 0; "Gain" = -4.2; "Q" = 1.0; };
                      }
                      {
                        type = "builtin";
                        name = "filter9";
                        label = "bq_lowshelf";
                        control = { "Freq" = 145; "Gain" = 4.2; "Q" = 0.8; };
                      }
                      {
                        type = "builtin";
                        name = "filter10";
                        label = "bq_lowshelf";
                        control = { "Freq" = 45; "Gain" = -2.2; "Q" = 0.9; };
                      }
                    ];
                    links = [
                      { output = "preamp:Out"; input = "filter9:In"; }
                      { output = "filter9:Out"; input = "filter10:In"; }
                    ];
                  };
                  "capture.props" = {
                    "node.name" = "effect_input.eq_shelves";
                    "media.class" = "Audio/Sink";
                    "audio.channels" = 2;
                    "audio.position" = [ "FL" "FR" ];
                  };
                  "playback.props" = {
                    "node.name" = "effect_output.eq_shelves";
                    "node.passive" = true;
                    "target.object" = "alsa_output.usb-GuangZhou_FiiO_Electronics_Co._Ltd_FIIO_BTR15_EQ-00.analog-stereo";
                    "audio.channels" = 2;
                    "audio.position" = [ "FL" "FR" ];
                  };
                };
              }
            ];
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
