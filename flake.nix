{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix = {
      url = "git+https://git.lix.systems/lix-project/lix.git";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix-module = {
      url = "git+https://git.lix.systems/lix-project/nixos-module.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
    agenix.url = "github:ryantm/agenix";
    stylix.url = "github:danth/stylix";
    preservation.url = "github:nix-community/preservation";
    flake-utils.url = "github:numtide/flake-utils";
    jovian.url = "github:jovian-experiments/jovian-nixos/development";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    run0-sudo-shim = {
      url = "github:lordgrimmauld/run0-sudo-shim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell { buildInputs = [ pkgs.nixpkgs-fmt ]; };
      }
    ))
    // {
      nixosConfigurations =
        let
          mkNixosSystem =
            {
              system,
              hostname,
              extraModules ? [ ],
            }:
            nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit inputs; };
              modules = [
                inputs.lix-module.nixosModules.default
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
                inputs.preservation.nixosModules.default
                inputs.stylix.nixosModules.stylix
                inputs.agenix.nixosModules.default
                inputs.home-manager.nixosModules.home-manager
                inputs.nix-index-database.nixosModules.nix-index
                inputs.run0-sudo-shim.nixosModules.default
                ./configuration.nix
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    extraSpecialArgs = { inherit inputs; };
                    users.codebam = {
                      imports = [ ./home.nix ];
                    };
                    sharedModules = [ inputs.agenix.homeManagerModules.default ];
                  };
                }
              ] ++ extraModules;
            };
        in
        {
          nixos-desktop = mkNixosSystem {
            system = "x86_64-linux";
            hostname = "nixos-desktop";
            extraModules = [
              ./desktop/configuration.nix
              {
                home-manager.users.codebam.imports = [ ./desktop/home.nix ];
                home-manager.users.makano.imports = [ ./desktop/makano-home.nix ];
              }
            ];
          };

          nixos-laptop = mkNixosSystem {
            system = "x86_64-linux";
            hostname = "nixos-laptop";
            extraModules = [
              ./laptop/configuration.nix
              { home-manager.users.codebam.imports = [ ./laptop/home.nix ]; }
            ];
          };
          nixos-steamdeck = mkNixosSystem {
            system = "x86_64-linux";
            hostname = "nixos-steamdeck";
            extraModules = [
              inputs.jovian.nixosModules.default
              ./steamdeck/configuration.nix
              { home-manager.users.codebam.imports = [ ./steamdeck/home.nix ]; }
            ];
          };
        };
    };
}
