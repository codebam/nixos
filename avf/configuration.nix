{ pkgs, lib, ... }:

{
  imports = [
    ../modules/users/default.nix
  ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  avf.defaultUser = "codebam";
  environment = {
    systemPackages = with pkgs; [
      dig
      git
      nushell
      unzip
      zip
      _7zz
      helix
    ];
  };
  services = {
    tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };
    openssh = {
      enable = true;
      ports = [ 8022 ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
      openFirewall = true;
    };
  };
  programs = {
    fish.enable = true;
  };
  system.stateVersion = "26.05";
}
