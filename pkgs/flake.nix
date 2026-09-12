{
  description = "codebam's standalone Nix packages";

  # The only input, deliberately. `nix run github:codebam/nixos?dir=pkgs#<name>`
  # must not drag in the parent flake's disko/lanzaboote/chaotic/... graph just
  # to build one tool, and it must stay pointable-at without cloning. The lock
  # pins the same nixpkgs revision as ../flake.lock, so a package is identical
  # whether it comes from here or from the parent flake's overlay.
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];

      # Same unfree predicate the hosts use (./unfree.nix), because three of
      # the derivations below (ssg, sigmashake-desktop, polariumcode) are
      # unfree and `nix flake check` forces every package.
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) (import ./unfree.nix);
            }
          )
        );
    in
    {
      # nix run / build / profile install ...?dir=pkgs#<name>
      packages = forAllSystems (pkgs: import ./default.nix { inherit pkgs; });

      # For a NixOS config that wants these as `pkgs.<name>`:
      #   nixpkgs.overlays = [ inputs.packages.overlays.default ];
      overlays.default = _final: _prev: import ./default.nix { pkgs = _final; };
    };
}
