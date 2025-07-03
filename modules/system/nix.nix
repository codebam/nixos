{ config, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "codebam"
      ];
      system-features = [
        "i686-linux"
        "big-parallel"
        "kvm"
      ];
      max-jobs = "auto";
      cores = 0;
      extra-sandbox-paths = [ config.programs.ccache.cacheDir ];
      builders-use-substitutes = true;
      substituters = [
        "https://cache.nixos.org/"
        "https://helix.cachix.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    # Enable automatic optimization of the store
    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };
  };
}
