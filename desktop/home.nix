{ pkgs, lib, inputs, ... }:

{
  programs = {
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