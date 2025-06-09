{ pkgs, ... }:

{
  age = {
    # identityPaths = [
    #   ./secrets/identities/yubikey-5c.txt
    #   ./secrets/identities/yubikey-5c-nfc.txt
    # ];
    secrets.duckdns-token.file = ../secrets/duckdns-token.age;
  };

  home = {
    packages = with pkgs; [
      prismlauncher
      vscode
    ];
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
        key = "0F6D5021A87F92BA";
        signByDefault = true;
      };
    };
    i3status-rust = {
      bars = {
        default = {
          settings = {
            theme = {
              theme = "ctp-mocha";
            };
          };
          icons = "awesome6";
          blocks = [
            { block = "focused_window"; }
            { block = "sound"; }
            {
              block = "sound";
              device_kind = "source";
            }
            {
              block = "music";
              format = "$icon {$combo.str(max_w:30,rot_interval:0.5) $prev $play $next |}";
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
              format = "$icon {$signal_strength $ssid|Wired connection}";
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
            {
              alert = 10.0;
              block = "disk_space";
              info_type = "available";
              interval = 60;
              path = "/backup";
              warning = 20.0;
            }
            {
              block = "memory";
              format = "$icon $mem_used_percents ";
            }
            {
              block = "amd_gpu";
              format = "$icon $utilization $vram_used_percents";
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
