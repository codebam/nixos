{ pkgs, ... }:
let
  # This nixpkgs revision emits `-Dmimalloc=<...>` for every Lix in
  # `lixPackageSets`, but Meson only knows that option from Lix 2.96 on and it
  # aborts on an unknown option (`ERROR: Unknown option: "mimalloc"`), so
  # nothing in the 2.95 scope -- 2.95.4 itself included -- builds. Upstream
  # fixed it for 2.95 in NixOS/nixpkgs 8d8ca25b ("drop unsupported option
  # mimalloc"), which is in master but not yet in nixos-unstable; drop all of
  # this once the nixpkgs input passes that commit.
  #
  # The override wraps the whole 2.95 scope rather than `nix.package` alone:
  # nix-eval-jobs, nixpkgs-review and colmena are built against the scope's own
  # Lix, so overriding only the package would leave the unbuildable derivation
  # in the closure. It is built from `prev` inside the overlay because the
  # scope's Lix consumers take their dependencies from the package set they were
  # created in -- doing it from `pkgs` makes colmena's own `.override` recurse.
  dropMimalloc =
    lixScope:
    lixScope.overrideScope (
      _lixFinal: lixPrev: {
        lix = lixPrev.lix.overrideAttrs (old: {
          mesonFlags = builtins.filter (f: !(builtins.isString f && pkgs.lib.hasPrefix "-Dmimalloc" f)) (
            old.mesonFlags or [ ]
          );
        });
      }
    );
in
{
  nixpkgs.overlays = [
    (
      _final: prev:
      let
        lixPackageSets = prev.lixPackageSets.extend (
          _: _: {
            lix_2_95 = dropMimalloc prev.lixPackageSets.lix_2_95;
          }
        );
      in
      {
        inherit lixPackageSets;

        inherit (lixPackageSets.latest)
          nixpkgs-review
          nix-eval-jobs
          nix-fast-build
          colmena
          ;
      }
    )
  ];

  nix.package = pkgs.lixPackageSets.latest.lix;
}
