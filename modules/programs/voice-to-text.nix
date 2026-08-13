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

    streaming = lib.mkEnableOption ''
      a second command, `voice-to-text-stream`, that types each utterance as
      it is spoken instead of the whole transcript at the end. Not per word:
      whisper is not a word-streaming recogniser, and the only append-only
      thing whisper-stream emits is one chunk per pause. What that buys is
      seeing the first sentence while still saying the third; what it costs is
      that each chunk is transcribed with no sight of the one before it, so
      wording across a pause is worse than the one-shot command's, and the
      model stays resident for the length of the session. Casing and
      punctuation are no longer part of that cost -- `plainifyArgs` removes
      both from either command's output.

      Turning this on does not replace `voice-to-text`, which stays installed
      -- but it does move the Viewport binding onto the streaming one
    '';

    gpu = lib.mkEnableOption ''
      the Vulkan whisper.cpp backend rather than the CPU one. It is not in the
      binary cache, so it costs a local compile of whisper.cpp, and it buys
      little for one dictated sentence: most of the wall clock there is
      loading the model and starting the process, which the GPU does not
      shorten. Worth it on a machine with a discrete card and a bigger model,
      not on a laptop
    '';

    plainifyArgs = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        lowercase = false;
        fillers = [ ];
      };
      description = ''
        Arguments for `pkgs/voice-to-text-plainify.nix`, which decides what
        both commands do to a transcript before typing it: fold to lowercase,
        drop sentence punctuation, drop hesitation noises. The defaults do all
        three, which is what dictation into a chat box or a shell wants.
        `{ lowercase = false; punctuation = ""; fillers = []; }` is whisper's
        own output verbatim.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.voice-to-text.override (
        {
          inherit (config.voiceToText) plainifyArgs;
        }
        // lib.optionalAttrs config.voiceToText.gpu { whisper-cpp = pkgs.whisper-cpp-vulkan; }
      );
      defaultText = lib.literalMD "`pkgs.voice-to-text`, Vulkan-backed when `gpu` is set";
      description = ''
        The dictation command as this host configures it. Whatever runs it has
        to name this rather than `pkgs.voice-to-text` -- the Viewport
        keybinding in home-manager does -- or `gpu` never reaches the thing
        being launched.
      '';
    };

    streamingPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.voice-to-text-stream.override (
        {
          inherit (config.voiceToText) plainifyArgs;
        }
        // lib.optionalAttrs config.voiceToText.gpu { whisper-cpp = pkgs.whisper-cpp-vulkan; }
      );
      defaultText = lib.literalMD "`pkgs.voice-to-text-stream`, Vulkan-backed when `gpu` is set";
      description = ''
        The streaming dictation command as this host configures it. Defined
        whether or not `streaming` is on, so the Viewport binding can pick
        between this and `package` in one expression; only installed when it
        is.
      '';
    };

    binding = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default =
        if config.voiceToText.streaming then
          config.voiceToText.streamingPackage
        else
          config.voiceToText.package;
      defaultText = lib.literalMD "`streamingPackage` when `streaming` is set, `package` otherwise";
      description = ''
        Which of the two commands a keybinding should launch. Here rather than
        in home-manager so the choice is made once, next to the options that
        decide it.
      '';
    };
  };

  config = lib.mkIf config.voiceToText.enable {
    environment.systemPackages = [
      config.voiceToText.package
    ]
    ++ lib.optional config.voiceToText.streaming config.voiceToText.streamingPackage;
  };
}
