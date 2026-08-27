# A sed program that turns a Voxtype transcript into what dictation into a
# chat box or a shell actually wants: one lowercase line, no sentence
# punctuation, none of the hesitation noises whisper faithfully writes down,
# and none of the sentences Whisper invents out of silence. Voxtype runs it as
# its output post-processing command before typing the result.
#
# This is post-processing rather than prompting on purpose. `--prompt` biases
# the decoder and is worth setting, but it is a suggestion the model is free to
# ignore mid-utterance. A sed program applied to the output is the only part of
# this that is deterministic.
#
# The rules run in a fixed order, and it matters: everything below the
# lowercasing is written expecting lowercase input, and the whole-line
# hallucination match has to happen after punctuation is gone and spacing is
# normalised or "Thank you." never matches "thank you".
{
  lib,

  # Fold everything to lowercase. The reason to turn this off is dictating
  # anything where a capital carries meaning -- proper nouns, acronyms, code.
  lowercase ? true,

  # Sentence punctuation whisper adds at every pause. Apostrophes and hyphens
  # are deliberately not in here: they are inside words ("don't", "well-known")
  # rather than between them, and removing them changes what was said.
  #
  # ASCII only, because this ends up in a sed bracket expression and the
  # commands run under whatever locale the compositor handed them -- under
  # LC_ALL=C a bracket expression holding a multi-byte character matches its
  # individual bytes, which can cut another UTF-8 character in half. The two
  # non-ASCII marks whisper actually emits are handled as whole-string
  # substitutions below, where byte matching is exact and harmless.
  punctuation ? ".,!?;:\"",

  # Hesitation noises, as extended regular expressions matched whole-word after
  # lowercasing. Written with `+` on the repeated letters because whisper spells
  # the same sound "um", "umm" and "ummm" depending on how long it ran.
  #
  # Only sounds, not the verbal fillers -- "like", "you know", "I mean". Those
  # are also words with meanings, and a filter that cannot tell "it looks like
  # this" from "it's, like, broken" silently rewrites what was said. Add them
  # here if you want them gone and can live with that.
  fillers ? [
    "u+m+h*"
    "u+h+"
    "e+r+m*"
    "hm+"
    "mm+"
    "mhm+"
    "ah+"
    "eh+"
  ],

  # What whisper transcribes silence as when it does not emit [BLANK_AUDIO]:
  # the phrases that end the YouTube videos its training data was scraped from.
  # Room noise through a VAD is enough to trigger one, so the streaming command
  # types "thank you" at nobody several times an hour without this.
  #
  # Matched against the whole line and only the whole line. "thank you" inside
  # a sentence is someone actually saying thank you; alone, right after a
  # pause, it is the model filling a gap it could not decode. This is why
  # single common words can be listed at all -- "you" as an entire utterance is
  # whisper's most frequent silence artefact, and as part of one it is
  # untouched.
  hallucinations ? [
    "thank you( very much)?"
    "thanks for watching"
    "thanks for watching!?"
    "please subscribe"
    "like and subscribe"
    "subtitles by the amara\\.org community"
    "subtitles by .*"
    "transcription by .*"
    "captions by .*"
    "you"
    "bye"
    "bye bye"
    "so"
    "okay"
    "oh"
    "the end"
    "\\.+"
  ],

  # Words the model gets wrong the same way every time. base.en has never heard
  # of any of this, so it writes the nearest English it knows and the correction
  # is mechanical. Keys are extended regular expressions matched whole-word
  # against lowercased text; values are literal replacements. Add whatever
  # vocabulary this machine dictates about -- this is the largest accuracy win
  # available short of a bigger model.
  substitutions ? {
    "nix os|next os|nick's os|nixos" = "nixos";
    "nix pkgs|nix packages" = "nixpkgs";
    "home manager" = "home-manager";
    "b cache fs|bcash fs|be cache fs" = "bcachefs";
    "pipe wire" = "pipewire";
    "way bar" = "waybar";
    "way land" = "wayland";
    "cloud flare" = "cloudflare";
    "rangler|wrangler" = "wrangler";
    "tail scale" = "tailscale";
    "system d" = "systemd";
    "git hub" = "github";
    "type script" = "typescript";
    "java script" = "javascript";
  },

  # Decoder loops repeat a word until the temperature fallback bails them out:
  # "the the the the". Collapsed to one occurrence.
  collapseRepeats ? true,

  # How many times in a row a word has to appear before the repeat is treated
  # as a decoder artefact rather than speech. Three, not two, because a doubled
  # word is ordinary English once punctuation has been stripped: "I tested it,
  # it looks like this" becomes "it it" with nothing left to distinguish it
  # from a stutter, and "had had", "that that" and "is is" are doubled even
  # with the comma. A word said three times over is not a sentence.
  repeatThreshold ? 3,

  # With punctuation stripped there is no way left to dictate a line break, so
  # one is given back as a phrase. Values are typed literally, except for
  # `\x03`: that is the sentinel both commands turn into a newline at the point
  # where it types. A real newline cannot travel through here -- it is a
  # record separator to the sed and awk this feeds, and the streaming pipeline
  # is line-oriented -- and `\v`, the obvious stand-in, is matched by
  # `[[:space:]]` and would be squeezed back into a space by the tidying pass.
  #
  # Keep in mind what a newline does where this gets typed: in a chat client
  # Enter sends the message. That is a reason to leave this at its default of
  # two deliberate multi-word phrases rather than adding "period" and "comma",
  # which also have the problem that people say them.
  spokenCommands ? {
    "new line" = "\\x03";
    "new paragraph" = "\\x03\\x03";
  },

  # "i think" is fine in a chat box and wrong in a commit message, and it is
  # the one capital that lowercasing gets objectively wrong rather than just
  # informally. Contractions included: "i'm", "i'll", "i've", "i'd", "i're".
  capitalizeI ? true,
}:

let
  # `\L&`, the `:label`/`t` loops and `\x01` are all GNU sed. Both commands
  # depends on GNU sed through `gnused` in its runtime inputs.
  lowercaseCmd = lib.optionalString lowercase "s/.*/\\L&/\n";

  fillerAlternation = lib.concatStringsSep "|" fillers;

  # One filler per pass, looping until a pass changes nothing: the separator is
  # part of the match, so "um uh well" cannot be done in a single global
  # substitution -- matching "um " consumes the space that "uh" needs to be
  # recognised as a word start. Every whole-word rule below loops for the same
  # reason.
  fillerCmd = lib.optionalString (fillers != [ ]) ''
    :f
    s/(^| )(${fillerAlternation})([ ${punctuation}]|$)/\1/
    tf
  '';

  punctuationCmd = lib.optionalString (punctuation != "") ''
    s/[${punctuation}]+//g
    s/…//g
    s/[—–]/ /g
  '';

  # Before the whole-line rules, so a line that is nothing but a hallucination
  # and a trailing space still matches; repeated at the very end for the gaps
  # the later rules leave behind.
  tidyCmd = ''
    s/[[:space:]]+/ /g
    s/^ //
    s/ $//
  '';

  hallucinationCmd = lib.optionalString (hallucinations != [ ]) (
    "/^(" + lib.concatStringsSep "|" hallucinations + ")$/d\n"
  );

  # Each match becomes a `\x02<n>\x02` placeholder rather than its replacement,
  # and the placeholders are expanded once every pattern has run. Substituting
  # the final text directly would hang the pipeline: a pattern that also
  # matches its own replacement -- "nixos" among the misspellings it corrects
  # -- rewrites the same word forever, and `t` branches back every time.
  # Placeholders cannot match any pattern, so every loop terminates.
  substitutionCmd =
    let
      patterns = lib.attrNames substitutions;
    in
    lib.concatStrings (
      lib.imap0 (i: pattern: ''
        :v${toString i}
        s/(^| )(${pattern})( |$)/\1\x02${toString i}\x02\3/
        tv${toString i}
      '') patterns
    )
    + lib.concatStrings (
      lib.imap0 (i: pattern: "s/\\x02${toString i}\\x02/${substitutions.${pattern}}/g\n") patterns
    );

  # Looped rather than global for the usual reason -- a run consumes the space
  # the next word start needs -- and the run has to be at least
  # `repeatThreshold` long, which is one more repetition than the `{n,}` count
  # (the first occurrence is matched separately, as the backreference source).
  repeatCmd = lib.optionalString collapseRepeats ''
    :r
    s/(^| )([a-z0-9'-]+)( \2){${toString (repeatThreshold - 1)},}( |$)/\1\2\4/
    tr
  '';

  spokenCmd = lib.concatStrings (
    lib.imap0 (i: phrase: ''
      :c${toString i}
      s/(^| )${phrase}( |$)/\1${spokenCommands.${phrase}}\2/
      tc${toString i}
    '') (lib.attrNames spokenCommands)
    ++ lib.optional (spokenCommands != { }) ''
      s/ *\x03 */\x03/g
    ''
  );

  capitalizeCmd = lib.optionalString (lowercase && capitalizeI) ''
    :i
    s/(^| )i('(m|ll|ve|d|re|s))?( |$)/\1I\2\4/
    ti
  '';
in
lowercaseCmd
+ fillerCmd
+ punctuationCmd
+ tidyCmd
+ hallucinationCmd
+ substitutionCmd
+ repeatCmd
+ spokenCmd
+ capitalizeCmd
+ tidyCmd
