{
  pkgs,
  config,
  lib,
  ...
}:

{

  systemd.user.services.pipewire.environment = {
    SPA_PLUGIN_DIR = lib.mkForce "${pkgs.pipewire}/lib/spa-0.2";
    LADSPA_PATH = lib.mkForce "${pkgs.lsp-plugins}/lib/ladspa:${pkgs.ladspaPlugins}/lib/ladspa:${pkgs.deepfilternet}/lib/ladspa";
    LV2_PATH = lib.mkForce "/run/current-system/sw/lib/lv2";
  };

  systemd.user.services.arrpc = {
    description = "arRPC - Discord RPC Bridge";
    unitConfig = {
      Requires = [ "dbus.socket" ];
      After = [
        "dbus.socket"
        "graphical-session.target"
      ];
    };
    serviceConfig = {
      ExecStart = "${pkgs.arrpc}/bin/arrpc";
      Restart = "always";
    };
    wantedBy = [ "default.target" ];
  };
  systemd.user.services.mprisence = {
    description = "Discord Rich Presence for MPRIS";
    unitConfig = {
      Requires = [ "dbus.socket" ];
      After = [
        "dbus.socket"
        "graphical-session.target"
      ];
    };
    serviceConfig = {
      ExecStart = "${pkgs.mprisence}/bin/mprisence";
      Restart = "always";
    };
    wantedBy = [ "default.target" ];
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
      environmentFile = config.sops.secrets.navidrome-lastfm.path;
      settings = {
        MusicFolder = "/home/codebam/Downloads/Lidarr";
        BaseUrl = "/navidrome";
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
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts."codebam.tplinkdns.com" = {
        addSSL = true;
        enableACME = true;
        locations."/" = {
          return = "301 https://$host/navidrome$request_uri";
        };
        locations."/navidrome" = {
          proxyPass = "http://127.0.0.1:4533";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Protocol $scheme;
          '';
        };
      };
      virtualHosts."music.codebam.ca" = {
        addSSL = true;
        enableACME = true;
        locations."/" = {
          return = "301 https://$host/navidrome$request_uri";
        };
        locations."/navidrome" = {
          proxyPass = "http://127.0.0.1:4533";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-Protocol $scheme;
          '';
        };
      };
    };
    timesyncd = {
      servers = [
        "time.cloudflare.com"
        "time.google.com"
      ];
      settings = {
        Time = {
          PollIntervalMaxSec = 64;
        };
      };
    };
    pipewire.wireplumber.extraConfig = {
      "99-media-stereo" = {
        "node.rules" = [
          {
            matches = [
              { "application.name" = "~.*"; }
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
      "99-game-stereo" = {
        "node.rules" = [
          {
            matches = [
              { "application.name" = "~(SDL Application.*|cs2.*)"; }
            ];
            actions = {
              "update-props" = {
                "audio.channels" = 6; # Assuming games want 5.1, or let them decide
                "audio.position" = null; # Reset to default
              };
            };
          }
        ];
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
    pipewire = {
      extraConfig = {
        pipewire-pulse = {
          "99-routing" = {
            "pulse.rules" = [
              {
                matches = [
                  { "application.name" = "~.*"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "media_ducker";
                    "target.object" = "media_ducker";
                  };
                };
              }
              {
                matches = [
                  { "application.name" = "~(SDL Application.*|cs2.*)"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "game_listen";
                    "target.object" = "game_listen";
                  };
                };
              }
            ];
          };
        };
        pipewire = {
          "99-input-denoising" = {
            "context.modules" = [
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "DeepFilterNet AI Noise Canceling";
                  "media.name" = "DeepFilterNet AI Noise Canceling";
                  "filter.smart" = true;
                  "filter.smart.name" = "deep_filter_chain";

                  "filter.graph" = {
                    nodes = [
                      {
                        type = "ladspa";
                        name = "deep_filter";
                        plugin = "${pkgs.deepfilternet}/lib/ladspa/libdeep_filter_ladspa.so";
                        label = "deep_filter_mono";
                        control = {
                          "Attenuation Limit (dB)" = 50.0;
                        };
                      }
                    ];
                    inputs = [ "deep_filter:Input" ];
                    outputs = [ "deep_filter:Output" ];
                  };

                  "capture.props" = {
                    "node.name" = "deep_filter_input";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [ "MONO" ];
                    "node.dont-fallback" = true;
                    "node.linger" = true;
                  };

                  "playback.props" = {
                    "node.name" = "deep_filter_output";
                    "media.class" = "Audio/Source";
                    "audio.position" = [ "MONO" ];
                    "node.passive" = true;
                  };
                };
              }
            ];
          };
          "99-routing" = {
            "node.rules" = [
              {
                matches = [
                  { "application.name" = "~.*"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "media_ducker";
                    "target.object" = "media_ducker";
                  };
                };
              }
              {
                matches = [
                  { "application.name" = "~(SDL Application.*|cs2.*)"; }
                  { "node.name" = "~(SDL Application.*|cs2.*)"; }
                ];
                actions = {
                  "update-props" = {
                    "node.target" = "game_listen";
                    "target.object" = "game_listen";
                  };
                };
              }
            ];
          };
          "99-game-ducking-system" = {
            "context.modules" = [
              # 1. Game Listen Sink: Direct to DAC
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "Game Listen";
                  "capture.props" = {
                    "node.name" = "game_listen";
                    "media.class" = "Audio/Sink";
                    "audio.position" = [
                      "FL"
                      "FR"
                    ];
                  };
                  "playback.props" = {
                    "node.name" = "game_listen_out";
                    "stream.dont-remix" = true;
                    "channelmix.upmix" = false;
                  };
                };
              }
              # 2. Sidechain Tap: Copies Game into Ducker channels 3-4 (Passive)
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = "Game Sidechain Tap";
                  "capture.props" = {
                    "node.target" = "game_listen";
                    "stream.capture.sink" = true;
                    "stream.dont-remix" = true;
                  };
                  "playback.props" = {
                    "node.target" = "media_ducker";
                    "node.passive" = true;
                    "stream.dont-remix" = true;
                    "audio.position" = [
                      "RL"
                      "RR"
                    ];
                  };
                };
              }
              # 3. The Ducker: 4-channel sink that only plays back channels 1-2
              {
                name = "libpipewire-module-filter-chain";
                args = {
                  "node.description" = "Media Ducker";
                  "filter.graph" = {
                    nodes = [
                      {
                        type = "lv2";
                        name = "ducker";
                        plugin = "http://lsp-plug.in/plugins/lv2/sc_compressor_stereo";
                        control = {
                          "sct" = 2.0;
                          "scm" = 0.0;
                          "scs" = 0.0;
                          "scp" = 1.0;
                          "scr" = 10.0;
                          "sla" = 5.0;
                          "al" = 0.0316;
                          "at" = 20.0;
                          "rt" = 100.0;
                          "cr" = 4.0;
                          "kn" = 0.501;
                          "mk" = 1.0;
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
                    "node.name" = "media_ducker";
                    "media.class" = "Audio/Sink";
                    "audio.channels" = 4;
                    "audio.position" = [
                      "FL"
                      "FR"
                      "RL"
                      "RR"
                    ];
                    "channelmix.upmix" = false; # Prevent media from bleeding into sidechain
                  };
                  "playback.props" = {
                    "node.name" = "media_ducker_out";
                    "stream.dont-remix" = true;
                    "channelmix.matrix" = [
                      [
                        1
                        0
                        0
                        0
                      ]
                      [
                        0
                        1
                        0
                        0
                      ]
                    ];
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
              "default.clock.rate" = 48000;
            };
          };
        };
      };
    };
    hardware.openrgb = {
      enable = true;
    };
    ollama = {
      enable = true;
      host = "0.0.0.0";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      };
    };
  };
}
