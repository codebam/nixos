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
    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-avf = {
      url = "github:nix-community/nixos-avf";
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
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ] (system: functionProvidedToForAllSystems nixpkgs.legacyPackages.${system});

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
            inputs.lsfg-vk-flake.nixosModules.default
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
          # Not nixpkgs.hostPlatform: the avf host sets `system` directly and
          # leaves that option undefined.
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
            ./steamdeck/configuration
            { home-manager.users.codebam.imports = [ ./steamdeck/home.nix ]; }
          ];
        };

        nixos-avf = inputs.nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            inputs.nixos-avf.nixosModules.avf
            ./avf/configuration.nix
          ];
        };
      };
    };
}
