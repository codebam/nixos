{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.voiceToText.enable = lib.mkEnableOption ''
    offline dictation: `voice-to-text` records from the default source,
    transcribes with whisper.cpp and types the result into the focused
    window. Nothing leaves the machine, and the model is fetched at build
    time rather than on first use -- so the cost is 148 MB of closure on
    every host that turns this on
  '';

  config = lib.mkIf config.voiceToText.enable {
    environment.systemPackages = [ pkgs.voice-to-text ];
  };
}
