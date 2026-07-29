{ config, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Store deduplication is handled by the weekly nix.optimise timer below;
      # auto-optimise-store would additionally hash every path on every build.
      trusted-users = [
        "root"
        "codebam"
      ];
      # No system-features override: "i686-linux" is a platform, not a feature
      # (extra-platforms already resolves to [aarch64-linux i686-linux] via
      # boot.binfmt), and big-parallel/kvm are NixOS defaults.
      max-jobs = "auto";
      cores = 0;
      extra-sandbox-paths = [ config.programs.ccache.cacheDir ];
      builders-use-substitutes = true;
      # The GCP cache is not listed here. It arrives with the viewport-smithay
      # module, which carries the bucket *and* the public key that makes its
      # narinfos acceptable — listed here as well, the URLs appeared twice in
      # nix.conf and the key still only came from the module.

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
