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
    };
    gc = {
      automatic = false;
    };
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
    flake = "/persistent/etc/nixos";
  };
}
