{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
      };
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    preservation.url = "github:nix-community/preservation";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned to main ~Aug 2025 (update deliberately: upstream breaks
    # the nixos module options every few months; bump with
    # `nix flake update lsfg-vk-flake` + a Deck rebuild to verify).
    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-pass = {
      url = "github:codebam/sops-pass";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    viewport = {
      url = "github:codebam/viewport";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned to v0.7.5 (update deliberately: whisper model behavior
    # and CLI flags shift between releases; bump + re-test dictation).
    voxtype = {
      url = "github:peteonrails/voxtype/v0.7.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      inherit (inputs.chaotic.vendored) jovian;
      forAllSystems =
        functionProvidedToForAllSystems:
        # Only the architectures this flake actually defines hosts for: every
        # extra system here is another full nixpkgs evaluation for devShells,
        # the formatter and checks.
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
        ] (system: functionProvidedToForAllSystems nixpkgs.legacyPackages.${system});

      # Unfree names the hosts permit, from the single shared list. The
      # standalone `packages` output below needs the same predicate: two local
      # derivations (ssg, sigmashake-desktop) are unfree, and `nix flake check`
      # forces every package, so without it the output would refuse to even
      # evaluate. The predicate is eval-only, so the store paths stay identical
      # to the ones the hosts install.
      unfreePackages = import ./unfree.nix;

      # Like forAllSystems, but evaluating under that unfree predicate.
      forAllSystemsUnfree =
        functionProvidedToForAllSystems:
        nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
          ]
          (
            system:
            functionProvidedToForAllSystems (
              import nixpkgs {
                inherit system;
                config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) unfreePackages;
              }
            )
          );

      # Helper function to define standard NixOS systems (Desktop, Laptop, Steamdeck)
      mkNixosSystem =
        {
          system,
          extraModules ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          # Pass all flake inputs to NixOS modules
          specialArgs = { inherit inputs; };
          modules = [
            inputs.disko.nixosModules.disko
            # Configured in modules/system/boot.nix, next to the systemd-boot
            # options it overrides.
            inputs.lanzaboote.nixosModules.lanzaboote
            inputs.preservation.nixosModules.default
            inputs.stylix.nixosModules.stylix
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            inputs.nix-index-database.nixosModules.nix-index
            inputs.chaotic.nixosModules.default
            # lsfg-vk intentionally not here: Steam Deck only, added
            # per-host below so other hosts skip the input entirely.
            ./modules
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # On file collision, move the existing file to <path>.hm-backup
                # and activate over it; clobber old backups instead of failing.
                backupFileExtension = "hm-backup";
                overwriteBackup = true;
                extraSpecialArgs = { inherit inputs; };
                users.codebam = {
                  imports = [
                    ./home
                  ];
                };
                sharedModules = [
                  inputs.sops-nix.homeManagerModules.sops
                  inputs.voxtype.homeManagerModules.default
                ];
              };
            }
          ]
          ++ extraModules;
        };

    in
    {
      # Each local derivation on its own, so anyone can install one without
      # adopting a host:
      #   nix run   github:codebam/nixos#ripwire
      #   nix build github:codebam/nixos#dsh
      #   nix profile install github:codebam/nixos#zvec-grep
      # `voxtype-plainify` is not here: it is a sed program, not a package
      # (see pkgs/default.nix).
      packages = forAllSystemsUnfree (pkgs: import ./pkgs { inherit pkgs; });

      # For a NixOS config or another flake that wants the same definitions as
      # `pkgs.<name>`:
      #   nixpkgs.overlays = [ inputs.nixos.overlays.default ];
      overlays.default = final: _prev: import ./pkgs { pkgs = final; };

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # `nix develop` execs whatever `bash` PATH resolves to, and the
            # stdenv default is built --disable-readline --disable-progcomp.
            # Without this, ~/.bashrc breaks and starship's PS1 escapes leak.
            bashInteractive
            nil
            nixd
            nixfmt
            statix
            deadnix
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      # `nix flake check` builds every host, so eval breakage is caught before
      # a rebuild rather than during one.
      checks = forAllSystems (
        pkgs:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
          # Keep a check's build to hosts on the same system, so adding an
          # aarch64 host later does not make the x86_64 pass try to build it.
          hostsFor = nixpkgs.lib.filterAttrs (
            _: cfg: cfg.pkgs.stdenv.hostPlatform.system == system
          ) inputs.self.nixosConfigurations;
        in
        nixpkgs.lib.mapAttrs (_: cfg: cfg.config.system.build.toplevel) hostsFor
        // {
          lint =
            let
              # Only the .nix files, plus statix.toml which statix reads for
              # its ignore list. `${./.}` would be the whole worktree, so the
              # check rebuilt whenever wallpaper.png or the README changed --
              # neither of which statix or deadnix ever looks at.
              inherit (nixpkgs.lib) fileset;
              src = fileset.toSource {
                root = ./.;
                fileset = fileset.unions [
                  (fileset.fileFilter (file: file.hasExt "nix") ./.)
                  ./statix.toml
                ];
              };
            in
            pkgs.runCommand "lint"
              {
                nativeBuildInputs = [
                  pkgs.statix
                  pkgs.deadnix
                ];
              }
              ''
                cd ${src}
                deadnix --fail .
                statix check .
                touch $out
              '';
        }
      );

      nixosConfigurations = {
        nixos-desktop = mkNixosSystem {
          system = "x86_64-linux";
          extraModules = [
            ./desktop/configuration
            ./desktop-laptop/configuration
            {
              home-manager.users.codebam.imports = [
                ./desktop/home.nix
                ./desktop-laptop/home.nix
              ];
              home-manager.users.makano.imports = [ ./desktop/makano-home.nix ];
            }
          ];
        };
        nixos-laptop = mkNixosSystem {
          system = "x86_64-linux";
          extraModules = [
            ./laptop/configuration
            ./desktop-laptop/configuration
            {
              home-manager.users.codebam.imports = [
                ./laptop/home.nix
                ./desktop-laptop/home.nix
              ];
            }
          ];
        };
        nixos-steamdeck = mkNixosSystem {
          system = "x86_64-linux";
          extraModules = [
            jovian.nixosModules.default
            inputs.lsfg-vk-flake.nixosModules.default
            ./steamdeck/configuration
            { home-manager.users.codebam.imports = [ ./steamdeck/home.nix ]; }
          ];
        };
      };
    };
}
