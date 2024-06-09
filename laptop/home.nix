{ pkgs, lib, inputs, ... }:

{
  programs = {
    git = {
      signing = {
        key = "097B3E3F284C7B4C";
        signByDefault = true;
      };
    };
    bash = {
      profileExtra = ''
        PATH="$HOME/.local/bin:$PATH"
        export PATH
      '';
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
            {
              block = "focused_window";
            }
            {
              block = "sound";
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
              block = "memory";
              format = " $icon $mem_used_percents ";
            }
            {
              block = "cpu";
            }
            {
              block = "load";
            }
            {
              block = "time";
              interval = 60;
            }
            {
              block = "battery";
            }
          ];
        };
      };
    };
  };
}
