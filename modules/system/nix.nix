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
      # The GCP cache is not listed here, and the note that used to explain
      # why is out of date: it said the bucket and its public key arrive with
      # the viewport-smithay module, and that module has been deleted. So
      # nothing configures this machine to *read* the bucket now.
      #
      # `services.gcp-builder` below still writes to it. That is a real
      # asymmetry rather than an oversight to fix in passing: the cache existed
      # to substitute a WebKit this machine would otherwise compile, and the
      # compositor's default backend no longer builds an engine at all. If a
      # reader is wanted again it has to be spelled out here — and it needs the
      # key as well as the URL, or nix reaches the bucket and rejects every
      # narinfo in it as unsigned, which fails silently and looks exactly like
      # a cache with nothing in it.
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
