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
    lix-module = {
      url = "git+https://git.lix.systems/lix-project/nixos-module.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
    agenix.url = "github:ryantm/agenix";
    stylix.url = "github:danth/stylix";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      commonModules = [
        inputs.lix-module.nixosModules.default
        inputs.impermanence.nixosModules.impermanence
        ./configuration.nix
        inputs.stylix.nixosModules.stylix
        inputs.agenix.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.codebam = {
            imports = [ ./home.nix ];
          };
          home-manager.sharedModules = [ inputs.agenix.homeManagerModules.default ];
        }
      ];
    in
    {
      nixosConfigurations = {
        nixos-desktop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./desktop/configuration.nix
            { home-manager.users.codebam.imports = [ ./desktop/home.nix ]; }
          ];
        };

        nixos-laptop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./laptop/configuration.nix
            { home-manager.users.codebam.imports = [ ./laptop/home.nix ]; }
          ];
        };
      };
    };
}
