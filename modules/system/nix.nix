_:
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
