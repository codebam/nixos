# voxtype's flake links `-lsqlite3` (libsqlite3-sys/rusqlite without the
# `bundled` feature) but never puts sqlite in buildInputs; it used to resolve
# only through a transitive input that nixpkgs f4a03c0 stopped providing.
# Add sqlite explicitly, then point the flake's own wrapper at the patched
# binary: the wrapper is a symlinkJoin whose `paths` is env-driven, so
# overriding it keeps the runtime PATH it adds (wtype, dotool, ydotool, ...).
{ pkgs, inputs }:
let
  vx = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system};

  withSqlite = drv: drv.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.sqlite ];
  });

  wrap = wrapped: patched: wrapped.overrideAttrs (_: { paths = [ patched ]; });
in
{
  default = wrap vx.default (withSqlite vx.voxtype-unwrapped);
  vulkan = wrap vx.vulkan (withSqlite vx.voxtype-vulkan-unwrapped);
}
