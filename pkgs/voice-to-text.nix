{
  lib,
  writeShellApplication,
  fetchurl,
  whisper-cpp,
  pipewire,
  wtype,
  wl-clipboard,
  libnotify,
  coreutils,
  gnused,

  # ggml-base.en, 148 MB: English-only, and the smallest model that segments
  # dictation into utterances rather than emitting one unbroken run of words.
  # Its punctuation and casing matter less than they used to -- `plainifyArgs`
  # below strips both -- but where it puts the boundaries still does. Override
  # both of these together for a bigger one -- every model is listed at
  # https://huggingface.co/ggerganov/whisper.cpp -- and get the hash from
  # `nix-prefetch-url` on the URL you picked.
  modelUrl ? "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
  modelHash ? "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=",

  language ? "en",

  # Passed through to ../pkgs/voice-to-text-plainify.nix, which is what makes
  # the transcript lowercase, unpunctuated and free of "um". Set to `{
  # lowercase = false; punctuation = ""; fillers = []; }` for whisper's own
  # output verbatim.
  plainifyArgs ? { },

  # An unpunctuated lowercase initial prompt is a decoder bias towards
  # unpunctuated lowercase output -- whisper continues the style it is given.
  # It is a suggestion rather than a rule, which is why the sed program above
  # exists as well; what it buys is that the sed has less to do, so fewer
  # sentences arrive already mangled into one word. whisper-stream has no
  # equivalent flag.
  initialPrompt ? "okay so here is the thing i was saying earlier about it and then what happened next",

  # How sure the decoder has to be that a segment is speech before it writes
  # anything down. whisper-cli's own default is 0.60, which on a quiet room
  # tone is low enough to produce a confident "thank you" from nothing. Raising
  # it is the half of the hallucination problem that the plainify filter cannot
  # reach: the filter deletes the stock phrases it knows, this stops some of
  # them being generated. Too high and quiet real speech is dropped instead.
  noSpeechThreshold ? 0.8,

  # A recording nobody stopped is a microphone left on. Two minutes is longer
  # than anything dictated into a text field and short enough that forgetting
  # about one costs a file, not a day of audio.
  maxSeconds ? 120,
}:

let
  model = fetchurl {
    url = modelUrl;
    hash = modelHash;
  };

  plainify = import ./voice-to-text-plainify.nix ({ inherit lib; } // plainifyArgs);
in
writeShellApplication {
  name = "voice-to-text";

  runtimeInputs = [
    whisper-cpp
    pipewire
    wtype
    wl-clipboard
    libnotify
    coreutils
    gnused
  ];

  # One command, pressed twice: the first press starts recording and the
  # second stops it and types what was said. A hold-to-talk binding would be
  # the other shape, and no compositor here can express it -- Viewport's
  # chords fire on press only, and sway's --release is a second binding with
  # no guarantee the two halves pair up.
  text = ''
    run="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voice-to-text"
    mkdir -p "$run"
    pidfile="$run/recorder.pid"
    wav="$run/take.wav"

    # Replacing rather than stacking: three of these fire per dictation, and a
    # notification centre that keeps them all turns a sentence into a column.
    note() {
      notify-send -a voice-to-text \
        -h string:x-canonical-private-synchronous:voice-to-text "$@" || true
    }

    if [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      pid=$(cat "$pidfile")
      rm -f "$pidfile"

      # See the `env --default-signal` below for why this can be relied on to
      # arrive at all.
      kill -TERM "$pid" 2>/dev/null || true

      # pw-record writes the RIFF sizes on the way out, so the file is not a
      # readable WAV until the process is actually gone. Polled rather than
      # waited on: the recorder belongs to the invocation that started it, and
      # this one is a different process with no claim on it. Five seconds is
      # far past a clean exit and short of hanging the binding.
      waited=0
      while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 100 ]; do
        sleep 0.05
        waited=$((waited + 1))
      done
      kill -KILL "$pid" 2>/dev/null || true

      note "Transcribing…"

      # -np -nt is the transcript alone, no timestamps and no progress; the
      # loader still writes to stderr. Newlines become spaces because the
      # target is a text field, and [BLANK_AUDIO] is what silence transcribes
      # to rather than nothing at all.
      text=$(whisper-cli -m ${model} -f "$wav" -l ${language} -nt -np \
          -nth ${toString noSpeechThreshold} \
          --prompt ${lib.escapeShellArg initialPrompt} 2>/dev/null |
        tr '\n' ' ' |
        sed -e 's/\[BLANK_AUDIO\]//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' |
        # Lowercase, drop sentence punctuation, drop "um", drop the sentences
        # whisper invents out of silence, fix the words it always gets wrong.
        # See ../pkgs/voice-to-text-plainify.nix for what each rule is for.
        sed -E ${lib.escapeShellArg plainify} |
        # The one place a newline is wanted: `\x03` is what "new line" became,
        # kept out of band until now because everything upstream of here is
        # line-oriented and a real newline would be a record separator to it.
        tr '\003' '\n')
      rm -f "$wav"

      if [ -z "$text" ]; then
        note "Nothing heard"
        exit 0
      fi

      # The clipboard first, and unconditionally: typing goes to whatever has
      # keyboard focus, and if that turned out to be the wrong window the
      # words are still somewhere.
      printf '%s' "$text" | wl-copy

      # wtype reads any argument starting with '-' as an option and has no
      # '--' terminator, so a transcript opening with a dash would be parsed
      # as flags. A leading space makes that impossible.
      case $text in
        -*) text=" $text" ;;
      esac
      wtype "$text"
      exit 0
    fi

    rm -f "$wav"
    note "Recording…"

    # `env --default-signal` because a recorder that cannot be signalled never
    # stops. Two things arrive from the compositor and stack up:
    #
    #   - Viewport blocks SIGINT and SIGTERM for its event loop, and a mask
    #     survives both fork and exec, so everything it spawns inherits it.
    #   - POSIX requires a non-interactive shell to start background jobs with
    #     SIGINT and SIGQUIT set to SIG_IGN.
    #
    # The recorder ends up with `SigBlk: 4002` and `SigIgn: 6` -- INT and TERM
    # blocked, INT and QUIT ignored, nothing caught -- so the second press
    # signals a process that cannot hear it, transcribes a file no one has
    # finalised, and says "Nothing heard" while a recorder is left running for
    # every press so far. `--default-signal` restores the default disposition
    # *and* unblocks, which is the only part of this a keybinding can fix.
    #
    # 16 kHz mono is what whisper resamples to anyway, so recording anything
    # richer is a bigger file and the same transcript.
    env --default-signal=INT,TERM \
      timeout ${toString maxSeconds} \
      pw-record --rate 16000 --channels 1 --format s16 "$wav" &
    echo $! > "$pidfile"
  '';

  meta = {
    description = "Toggle dictation: record, transcribe with whisper.cpp, type the result";
    mainProgram = "voice-to-text";
    platforms = lib.platforms.linux;
  };
}
