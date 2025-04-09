{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    # staging.url = "github:nixos/nixpkgs/staging";
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
    agenix.url = "github:ryantm/agenix";
    stylix.url = "github:danth/stylix";
    # sops-nix.url = "github:Mic92/sops-nix";
    # rocm = {
    #   url = "github:lunnova/nixpkgs/rocm-update";
    # };
    # linux-custom = {
    #   url = "path:/home/codebam/git/linux";
    #   flake = false;
    # };
    # firefox-nightly.url = "github:nix-community/flake-firefox-nightly";
    # mesa-25.url = "github:K900/nixpkgs/mesa-25.0";
    # gen-nvim.url = "github:codebam/nixpkgs/gen-nvim";
    # catppuccin.url = "github:catppuccin/nix";
    # plasma-manager = {
    #   url = "github:nix-community/plasma-manager";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.home-manager.follows = "home-manager";
    # };
    rocm.url = "github:LunNova/nixpkgs/rocm-update";
    ollama.url = "github:codebam/nixpkgs/ollama-staging-into-master";
    avante.url = "github:codebam/nixpkgs/avante";
    libvirt.url = "github:codebam/nixpkgs/libvirt-sockets";
    xanmod.url = "github:codebam/nixpkgs/update-xanmod";
  };

  outputs =
    {
      nixpkgs,
      lix-module,
      home-manager,
      lanzaboote,
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
          lanzaboote.nixosModules.lanzaboote
          (
            { pkgs, lib, ... }:
            {
              environment.systemPackages = [ pkgs.sbctl ];
              boot.loader.systemd-boot.enable = lib.mkForce false;
              boot.lanzaboote = {
                enable = true;
                pkiBundle = "/etc/secureboot";
              };
            }
          )
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
            home-manager.sharedModules = [ ];
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
          lanzaboote.nixosModules.lanzaboote
          (
            { pkgs, lib, ... }:
            {
              environment.systemPackages = [ pkgs.sbctl ];
              boot.loader.systemd-boot.enable = lib.mkForce false;
              boot.lanzaboote = {
                enable = true;
                pkiBundle = "/etc/secureboot";
              };
            }
          )
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
            home-manager.sharedModules = [ ];
          }
        ];
      };
    };
}
