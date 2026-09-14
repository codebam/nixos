{ lib, ... }:
let
  profiles = import ./nono-profiles.nix;
in
{
  # The profiles are read-only store symlinks on purpose: a sandboxed process
  # must not be able to rewrite the rules it is running under, and a rebuild
  # keeps them in step with the nono version in this flake.
  xdg.configFile = lib.mapAttrs' (
    name: profile:
    lib.nameValuePair "nono/profiles/${name}.json" {
      text = builtins.toJSON profile;
    }
  ) profiles;
}
