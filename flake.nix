{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    catppuccin.url = "github:catppuccin/nix?rev=ccc188e244e8fb3248e3c8f19f70280076bf1408";
    gen-nvim-latest-pin.url = "github:codebam/nixpkgs/gen-nvim";
    wmenu-latest-pin.url = "github:codebam/nixpkgs/wmenu";
    bcachefs-master-pin.url = "github:koverstreet/bcachefs-tools?ref=0728677cdc325d3f9ff37f6a665eca13af5e50cc";
    bcachefs-custom-pin.url = "github:codebam/bcachefs-tools/fix2";
    linux-testing-update.url = "github:codebam/nixpkgs/linux_testing";
  };

  outputs = { nixpkgs, home-manager, catppuccin, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        catppuccin.nixosModules.catppuccin
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.codebam = {
            imports = [
              ./home.nix
              catppuccin.homeManagerModules.catppuccin
            ];
          };
        }
      ];
    };
  };
}
