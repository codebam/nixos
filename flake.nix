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
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
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
    sway-master.url = "github:codebam/nixpkgs/sway-master";
    mnw.url = "github:gerg-l/mnw";
    linux-firmware.url = "github:nixos/nixpkgs/12a55407652e04dcf2309436eb06fef0d3713ef3";
  };

  outputs =
    { nixpkgs
    , flake-utils
    , ...
    }@inputs:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nil
            nixd
            nixpkgs-fmt
            stylua
          ];
        };
      }
    ))
    // {
      nixosConfigurations =
        let
          mkNixosSystem =
            { system
            , extraModules ? [ ]
            ,
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
                ./configuration
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    extraSpecialArgs = { inherit inputs; };
                    users.codebam = {
                      imports = [ ./home ];
                    };
                    sharedModules = [
                      inputs.agenix.homeManagerModules.default
                      # inputs.nixvim.homeManagerModules.nixvim
                      inputs.mnw.homeManagerModules.default
                    ];
                  };
                }
              ] ++ extraModules;
            };
        in
        {
          nixos-desktop = mkNixosSystem {
            system = "x86_64-linux";
            extraModules = [
              ./desktop/configuration
              {
                home-manager.users.codebam.imports = [ ./desktop/home.nix ];
                home-manager.users.makano.imports = [ ./desktop/makano-home.nix ];
              }
            ];
          };
          nixos-laptop = mkNixosSystem {
            system = "x86_64-linux";
            extraModules = [
              ./laptop/configuration
              { home-manager.users.codebam.imports = [ ./laptop/home.nix ]; }
            ];
          };
          nixos-steamdeck = mkNixosSystem {
            system = "x86_64-linux";
            extraModules = [
              inputs.jovian.nixosModules.default
              ./steamdeck/configuration
              { home-manager.users.codebam.imports = [ ./steamdeck/home.nix ]; }
            ];
          };
        };
    };
}
