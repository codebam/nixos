_:

{
  # Not in modules/default.nix on purpose -- the laptop must not get Steam.
  imports = [ ../../modules/programs/gaming.nix ];

  gaming.extest = true;

  # Van Gogh is RDNA2, so radv runs the Vulkan build here as well as it does
  # on the desktop. The overlay pins the backend flags rather than reading
  # `config.rocmSupport`, which makes it the same derivation on both -- so
  # this costs the Deck's four cores nothing as long as it can substitute
  # what the desktop already built.
  voiceToText = {
    enable = true;
    gpu = true;
  };
}
