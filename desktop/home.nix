{ pkgs, lib, inputs, ... }:

{
  programs = {
    git = {
      signing = {
        key = "0F6D5021A87F92BA";
        signByDefault = true;
      };
    };
    bash = {
      profileExtra = ''
        PATH="$HOME/.local/bin:$PATH"
        export PATH
        WLR_RENDERER=vulkan
        export WLR_RENDERER
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
              block = "amd_gpu";
              format = " $icon $utilization $vram_used_percents";
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
          ];
        };
      };
    };
  };
}
