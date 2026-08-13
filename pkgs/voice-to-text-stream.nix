{
  lib,
  writeShellApplication,
  fetchurl,
  whisper-cpp,
  wtype,
  wl-clipboard,
  libnotify,
  coreutils,
  gnused,
  gawk,

  # Same model and default as the one-shot command, for the same reason: the
  # smallest one that segments rather than running everything together. VAD
  # mode transcribes each utterance with `no_context`, so every chunk is
  # decoded with no sight of the sentence it continues -- which is exactly the
  # case where a model that cannot find utterance boundaries falls apart.
  modelUrl ? "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
  modelHash ? "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=",

  language ? "en",

  # Passed through to ./voice-to-text-plainify.nix, exactly as in
  # voice-to-text.nix -- lowercase, no sentence punctuation, no "um". It does
  # more here than there: chunk-boundary punctuation is the thing VAD mode is
  # worst at, and deleting it removes the artefact instead of improving it.
  plainifyArgs ? { },

  # `--step 0` picks whisper-stream's VAD mode over its sliding window. The
  # window mode re-emits a revised transcript of the last `--length` on every
  # step -- `single_segment` plus a `\33[2K\r` before each print -- so typing
  # it live would mean unwriting what changed with synthetic backspaces into
  # whatever field has focus. VAD mode is append-only: it waits for a pause,
  # transcribes one utterance and prints it once.
  #
  # `--length` is the window it grabs when the VAD fires, and stream.cpp takes
  # the last N ms of a ring buffer it never clears, gated to one transcription
  # every 2s. Anything much above that gap re-transcribes audio already typed;
  # 3000 keeps the overlap to roughly one utterance, which the deduplication
  # below is sized for.
  lengthMs ? 3000,

  # Voice activity threshold. Higher is deafer. 0.6 is stream.cpp's own
  # default and is worth turning down on a quiet mic that gets ignored, or up
  # in a room that keeps triggering it.
  vadThreshold ? 0.6,

  # Unlike the one-shot recorder there is no second press implied by the
  # first, so a forgotten session is a resident model and a live microphone.
  # Fifteen minutes is past any dictation and short of an afternoon.
  maxSeconds ? 900,
}:

let
  model = fetchurl {
    url = modelUrl;
    hash = modelHash;
  };

  plainify = import ./voice-to-text-plainify.nix ({ inherit lib; } // plainifyArgs);
in
writeShellApplication {
  name = "voice-to-text-stream";

  runtimeInputs = [
    whisper-cpp
    wtype
    wl-clipboard
    libnotify
    coreutils
    gnused
    gawk
  ];

  # No pipewire in runtimeInputs: whisper-stream captures through SDL rather
  # than pw-record, and SDL3 has the pipewire backend on its own RPATH.
  #
  # Same two-press shape as the one-shot command, and the same reason -- no
  # compositor here can express hold-to-talk. What differs is that the first
  # press leaves a whole pipeline running rather than one recorder, so the
  # thing the second press has to kill is a process group.
  text = ''
    run="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/voice-to-text"
    mkdir -p "$run"
    pgidfile="$run/stream.pgid"

    note() {
      notify-send -a voice-to-text \
        -h string:x-canonical-private-synchronous:voice-to-text "$@" || true
    }

    # Reads deduplicated chunks and types them. The clipboard is rewritten
    # with the whole transcript after every chunk rather than once at the end:
    # the end is a SIGTERM to this process group, and anything that tried to
    # run there would be racing its own death.
    type_stream() {
      local acc="" chunk out
      while IFS= read -r chunk; do
        [ -n "$chunk" ] || continue

        # The space between chunks trails this one rather than leading the
        # next. A wtype invocation whose first character is a space loses it:
        # every chunk here is a separate process, each uploading its own
        # keymap before typing, and the first key of the burst goes out while
        # the focused client is still on the previous map. Letters survive it
        # and a leading space does not. Trailing means no invocation ever
        # opens with one, at the cost of a space left after the last chunk.
        out="$chunk "
        acc="$acc$out"

        printf '%s' "$acc" | wl-copy

        # `--` ends option parsing, so a chunk opening with a dash is typed
        # rather than read as flags. wtype 0.4 does have the terminator --
        # the comment in voice-to-text.nix saying otherwise is wrong, though
        # the leading-space workaround it describes is harmless there.
        wtype -- "$out"
      done
    }

    # What `setsid` below starts. $$ is the session and process-group leader
    # here, so the file holds a group id and the second press can take the
    # whole pipeline down with one signal.
    if [ "''${1:-}" = "--session" ]; then
      echo $$ > "$pgidfile"

      # -1 on the exit status is expected: the second press kills this group,
      # and pipefail would otherwise make that look like a failure.
      #
      # `--foreground` is load-bearing rather than cosmetic. Without it
      # `timeout` puts itself in a new process group so it can signal its
      # child's group on expiry -- which takes whisper-stream out of the group
      # this file just recorded, so the second press kills the sed, the awk and
      # the typing loop and leaves the recorder holding the microphone until it
      # next writes into a closed pipe. `--foreground` skips the setpgid and
      # signals the direct child instead, which is all there is to signal here.
      timeout --foreground ${toString maxSeconds} \
        whisper-stream -m ${model} -l ${language} \
          --step 0 --length ${toString lengthMs} -vth ${toString vadThreshold} \
          2>/dev/null |
        # VAD mode forces timestamps back on (stream.cpp sets `no_timestamps =
        # !use_vad`), so each segment arrives as `[t0 --> t1]  text` between
        # `### Transcription N START/END` banners. Bracketed leftovers are
        # whisper's non-speech annotations -- [BLANK_AUDIO], [ Silence ] --
        # which are what a pause transcribes to rather than nothing at all.
        sed -u \
          -e '/^###/d' \
          -e 's/^\[[0-9:.]\{1,\} --> [0-9:.]\{1,\}\][[:space:]]*//' \
          -e 's/\[[^][]*\]//g' \
          -e 's/[[:space:]]\{1,\}/ /g' \
          -e 's/^ //' -e 's/ $//' |
        # Lowercase, drop sentence punctuation, drop "um" -- before the
        # deduplication rather than after it, so the overlap comparison and
        # the typed text are the same string. A chunk that was nothing but a
        # hesitation comes out empty here and the awk drops it.
        sed -E -u ${lib.escapeShellArg plainify} |
        # The ring buffer whisper-stream grabs from is never cleared, so
        # consecutive utterances share audio and the tail of what was already
        # typed comes back as the head of the next chunk. Emit only the part
        # that is not a continuation: find the longest suffix of the words so
        # far that matches the start of this chunk, and print the rest.
        # Matching is on lowercased, punctuation-stripped words, because the
        # same audio transcribed twice differs in exactly those.
        gawk -v maxov=12 '
          function nrm(s) { s = tolower(s); gsub(/[^a-z0-9]/, "", s); return s }
          NF == 0 { next }
          {
            maxk = (h < NF) ? h : NF
            if (maxk > maxov) maxk = maxov
            best = 0
            for (k = maxk; k >= 1; k--) {
              ok = 1
              for (i = 1; i <= k; i++) {
                if (hist[h - k + i] != nrm($i)) { ok = 0; break }
              }
              if (ok) { best = k; break }
            }
            out = ""
            for (i = best + 1; i <= NF; i++) {
              out = (out == "") ? $i : out " " $i
              hist[++h] = nrm($i)
            }
            if (out != "") { print out; fflush() }
          }
        ' |
        type_stream || true

      exit 0
    fi

    if [ -s "$pgidfile" ] && kill -0 -"$(cat "$pgidfile")" 2>/dev/null; then
      pgid=$(cat "$pgidfile")
      rm -f "$pgidfile"
      kill -TERM -"$pgid" 2>/dev/null || true
      note "Dictation stopped"
      exit 0
    fi

    note "Dictating…"

    # `env --default-signal` for the reason spelled out in voice-to-text.nix:
    # Viewport blocks INT and TERM for its event loop, the mask survives fork
    # and exec, and a session that cannot be signalled never stops. It has to
    # come before `setsid` so the restored disposition is what gets inherited.
    #
    # `setsid` execs in place rather than forking here -- a background job of
    # a shell without job control is not a process group leader -- so the
    # session leader keeps this pid and $$ in the branch above is the group.
    env --default-signal=INT,TERM setsid "$0" --session &
  '';

  meta = {
    description = "Toggle streaming dictation: whisper.cpp types each utterance as it is spoken";
    mainProgram = "voice-to-text-stream";
    platforms = lib.platforms.linux;
  };
}
