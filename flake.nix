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
    impermanence.url = "github:nix-community/impermanence";
    flake-utils.url = "github:numtide/flake-utils";

  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.nixpkgs-fmt ];
        };
      }
    ))
    //
    {
      nixosConfigurations =
        let
          mkNixosSystem = { system, hostname, extraModules ? [] }:
            nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit inputs; };
              modules = [
                inputs.lix-module.nixosModules.default
                inputs.disko.nixosModules.disko
                inputs.impermanence.nixosModules.impermanence
                inputs.stylix.nixosModules.stylix
                inputs.agenix.nixosModules.default
                inputs.home-manager.nixosModules.home-manager
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
              { home-manager.users.codebam.imports = [ ./desktop/home.nix ]; }
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
        };
    };
}
