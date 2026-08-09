{ pkgs, ... }:

{
  imports = [
    ../modules/users/default.nix
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  documentation.enable = false;
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
      # Tailnet-only, same as the other hosts: port 8022 is never opened on a
      # real interface, and tailscale0 is trusted below.
      openFirewall = false;
    };
  };
  # This host has no networking block of its own, so the tailscale0 trust that
  # modules/system/networking.nix gives the other hosts has to be stated here.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  programs = {
    fish.enable = true;
  };
  system.stateVersion = "26.05";
}
