_:

{
  # The two hosts with a microphone and a graphical session. Not in
  # modules/default.nix on purpose -- the Steam Deck would pay 148 MB of model
  # for a keybinding it has no keyboard to press.
  voiceToText.enable = true;
}
