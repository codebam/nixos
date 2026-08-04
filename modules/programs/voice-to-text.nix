{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.voiceToText = {
    enable = lib.mkEnableOption ''
      offline dictation: `voice-to-text` records from the default source,
      transcribes with whisper.cpp and types the result into the focused
      window. Nothing leaves the machine, and the model is fetched at build
      time rather than on first use -- so the cost is 148 MB of closure on
      every host that turns this on
    '';

    gpu = lib.mkEnableOption ''
      the Vulkan whisper.cpp backend rather than the CPU one. It is not in the
      binary cache, so it costs a local compile of whisper.cpp, and it buys
      little for one dictated sentence: most of the wall clock there is
      loading the model and starting the process, which the GPU does not
      shorten. Worth it on a machine with a discrete card and a bigger model,
      not on a laptop
    '';

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default =
        if config.voiceToText.gpu then
          pkgs.voice-to-text.override { whisper-cpp = pkgs.whisper-cpp-vulkan; }
        else
          pkgs.voice-to-text;
      defaultText = lib.literalMD "`pkgs.voice-to-text`, Vulkan-backed when `gpu` is set";
      description = ''
        The dictation command as this host configures it. Whatever runs it has
        to name this rather than `pkgs.voice-to-text` -- the Viewport
        keybinding in home-manager does -- or `gpu` never reaches the thing
        being launched.
      '';
    };
  };

  config = lib.mkIf config.voiceToText.enable {
    environment.systemPackages = [ config.voiceToText.package ];
  };
}
