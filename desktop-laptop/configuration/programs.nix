_:

{
  # The Steam Deck turns this on for itself, in its own programs.nix. Named
  # per host rather than defaulted on in modules/default.nix even so: the
  # model is 148 MB of closure, which is not something a host should acquire
  # by importing the shared modules.
  voiceToText = {
    enable = true;

    # Mouse5 launches the streaming command rather than the one-shot one. The
    # one-shot stays installed and is still worth reaching for by name when a
    # sentence has to come out punctuated in one piece.
    streaming = true;
  };
}
