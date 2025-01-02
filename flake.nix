{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    # master.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin.url = "github:catppuccin/nix";
    # staging-next.url = "github:nixos/nixpkgs/staging-next";
  };

  outputs = { nixpkgs, home-manager, catppuccin, lanzaboote, ... }@inputs: {
    nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        ./desktop/configuration.nix
        ./desktop/rgb.nix
        catppuccin.nixosModules.catppuccin
        lanzaboote.nixosModules.lanzaboote
        ({ pkgs, lib, ... }: {
          environment.systemPackages = [
            pkgs.sbctl
          ];
          boot.loader.systemd-boot.enable = lib.mkForce false;
          boot.lanzaboote = {
            enable = true;
            pkiBundle = "/etc/secureboot";
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.codebam = {
            imports = [
              ./home.nix
              ./desktop/home.nix
              catppuccin.homeManagerModules.catppuccin
            ];
          };
        }
      ];
    };
    nixosConfigurations.nixos-laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        ./laptop/configuration.nix
        catppuccin.nixosModules.catppuccin
        lanzaboote.nixosModules.lanzaboote
        ({ pkgs, lib, ... }: {
          environment.systemPackages = [
            pkgs.sbctl
          ];
          boot.loader.systemd-boot.enable = lib.mkForce false;
          boot.lanzaboote = {
            enable = true;
            pkiBundle = "/etc/secureboot";
          };
        })
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.codebam = {
            imports = [
              ./home.nix
              ./laptop/home.nix
              catppuccin.homeManagerModules.catppuccin
            ];
          };
        }
      ];
    };
  };
}
