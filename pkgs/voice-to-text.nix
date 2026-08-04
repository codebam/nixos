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

  # ggml-base.en, 148 MB: English-only, and the smallest model that punctuates
  # dictation rather than emitting one unbroken sentence. Override both of
  # these together for a bigger one -- every model is listed at
  # https://huggingface.co/ggerganov/whisper.cpp -- and get the hash from
  # `nix-prefetch-url` on the URL you picked.
  modelUrl ? "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
  modelHash ? "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=",

  language ? "en",

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
      kill -INT "$pid" 2>/dev/null || true

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

      note "Transcribing…"

      # -np -nt is the transcript alone, no timestamps and no progress; the
      # loader still writes to stderr. Newlines become spaces because the
      # target is a text field, and [BLANK_AUDIO] is what silence transcribes
      # to rather than nothing at all.
      text=$(whisper-cli -m ${model} -f "$wav" -l ${language} -nt -np 2>/dev/null |
        tr '\n' ' ' |
        sed -e 's/\[BLANK_AUDIO\]//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
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

    # 16 kHz mono is what whisper resamples to anyway, so recording anything
    # richer is a bigger file and the same transcript.
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
