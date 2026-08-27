{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  plainify = import ../pkgs/voxtype-plainify.nix { inherit lib; };
  plainifyCommand = pkgs.writeShellApplication {
    name = "voxtype-plainify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      sed -E ${lib.escapeShellArg plainify} | tr '\003' '\n'
    '';
  };
in
{
  programs.voxtype = {
    enable = true;
    package = lib.mkDefault inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.default;
    model.name = "base.en";
    service.enable = true;

    settings = {
      state_file = "auto";

      hotkey.enabled = false;

      audio.max_duration_secs = 120;

      whisper = {
        language = "en";
        translate = false;
        on_demand_loading = false;
      };

      output = {
        mode = "type";
        fallback_to_clipboard = true;
        post_process = {
          command = lib.getExe plainifyCommand;
          timeout_ms = 5000;
          fallback_on_empty = false;
        };
        notification = {
          on_recording_start = true;
          on_recording_stop = true;
          on_transcription = true;
        };
      };
    };
  };
}
