_:

{
  # The Steam Deck turns this on for itself, in its own programs.nix. Named
  # per host rather than defaulted on in modules/default.nix even so: the
  # model is 148 MB of closure, which is not something a host should acquire
  # by importing the shared modules.
  voiceToText.enable = true;
}
