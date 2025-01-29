{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    # staging-next.url = "github:nixos/nixpkgs/staging-next";
    # master.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
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
    catppuccin.url = "github:catppuccin/nix";
    flatpak-stable.url = "github:getchoo-contrib/nixpkgs/pkgs/flatpak/1.16.0";
  };

  outputs = { nixpkgs, home-manager, catppuccin, lanzaboote, lix-module, lix, ... }@inputs: {
    nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        ./desktop/configuration.nix
        lix-module.nixosModules.default
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
