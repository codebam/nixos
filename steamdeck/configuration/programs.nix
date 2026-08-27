_:

{
  # Not in modules/default.nix on purpose -- the laptop must not get Steam.
  imports = [ ../../modules/programs/gaming.nix ];

  gaming.extest = true;

}
