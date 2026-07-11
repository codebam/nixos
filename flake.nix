{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    master.url = "github:nixos/nixpkgs/master";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix = {
      url = "git+https://git.lix.systems/lix-project/lix.git";
      flake = false;
    };
    lix-module = {
      url = "git+https://git.lix.systems/lix-project/nixos-module.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
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
    agenix = {
      url = "github:ryantm/agenix";
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
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      inherit (inputs.chaotic.vendored) jovian;
      forAllSystems =
        functionProvidedToForAllSystems:
        nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
          (
            system:
            functionProvidedToForAllSystems (
              import nixpkgs {
                inherit system;
                overlays = [
                ];
                config = {
                  # You can add common pkgs configurations here, e.g.:
                  # allowUnfree = true;
                  cudaSupport = false;
                };
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
            inputs.lanzaboote.nixosModules.lanzaboote
            (
              { pkgs, lib, ... }:
              {
                environment.systemPackages = [ pkgs.sbctl ];
                boot.loader.systemd-boot.enable = lib.mkForce false;
                boot.lanzaboote = {
                  enable = true;
                  pkiBundle = "/var/lib/sbctl";
                };
              }
            )
            inputs.lix-module.nixosModules.default
            inputs.preservation.nixosModules.default
            inputs.stylix.nixosModules.stylix
            inputs.agenix.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            inputs.nix-index-database.nixosModules.nix-index
            inputs.chaotic.nixosModules.default
            inputs.lsfg-vk-flake.nixosModules.default
            ./modules
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                users.codebam = {
                  imports = [
                    ./home
                  ];
                };
                sharedModules = [
                  inputs.agenix.homeManagerModules.default
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
            nil
            nixd
            nixpkgs-fmt
            nixfmt
          ];
        };
      });

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
