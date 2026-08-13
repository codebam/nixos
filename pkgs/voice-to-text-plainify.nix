# A sed program that turns a whisper transcript into what dictation into a
# chat box or a shell actually wants: one lowercase line, no sentence
# punctuation, and none of the hesitation noises whisper faithfully writes
# down. Shared by `voice-to-text` and `voice-to-text-stream` so the two
# commands cannot drift apart on what "plain" means.
#
# This is post-processing rather than prompting on purpose. `--prompt` biases
# the decoder and is worth setting, but it is a suggestion the model is free to
# ignore mid-utterance -- and whisper-stream has no `--prompt` at all. A sed
# program applied to the output is the only part of this that is deterministic.
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
}:

let
  # `\L&` is GNU sed; so is the `:label`/`t` loop below. Both commands already
  # depend on GNU sed through `gnused` in their runtime inputs.
  lowercaseCmd = lib.optionalString lowercase "s/.*/\\L&/\n";

  alternation = lib.concatStringsSep "|" fillers;

  # One filler per pass, looping until a pass changes nothing: the separator is
  # part of the match, so "um uh well" cannot be done in a single global
  # substitution -- matching "um " consumes the space that "uh" needs to be
  # recognised as a word start.
  fillerCmd = lib.optionalString (fillers != [ ]) ''
    :f
    s/(^| )(${alternation})([ ${punctuation}]|$)/\1/
    tf
  '';

  punctuationCmd = lib.optionalString (punctuation != "") ''
    s/[${punctuation}]+//g
    s/…//g
    s/[—–]/ /g
  '';
in
# Squeezing and trimming last, unconditionally: every rule above leaves the
# gap where what it deleted used to be.
''
  ${lowercaseCmd}${fillerCmd}${punctuationCmd}s/[[:space:]]+/ /g
  s/^ //
  s/ $//
''
