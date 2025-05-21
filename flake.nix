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
  };

  outputs =
    {
      nixpkgs,
      lix-module,
      home-manager,
      agenix,
      stylix,
      ...
    }@inputs:
    {
      nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          lix-module.nixosModules.default
          ./configuration.nix
          ./desktop/configuration.nix
          stylix.nixosModules.stylix
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.codebam = {
              imports = [
                ./home.nix
                ./desktop/home.nix
              ];
            };
            home-manager.sharedModules = [ agenix.homeManagerModules.default ];
          }
        ];
      };
      nixosConfigurations.nixos-laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          lix-module.nixosModules.default
          ./configuration.nix
          ./laptop/configuration.nix
          stylix.nixosModules.stylix
          agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.codebam = {
              imports = [
                ./home.nix
                ./laptop/home.nix
              ];
            };
            home-manager.sharedModules = [ agenix.homeManagerModules.default ];
          }
        ];
      };
    };
}
