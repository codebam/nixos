{ config, lib, ... }:
{
  nix = {
    settings = {
      # The desktop serves its own store over the tailnet
      # (desktop/configuration/nix-serve.nix). Everything the other two hosts
      # would otherwise compile -- the chaotic `_git` builds, the viewport
      # flakes, every override in nixpkgs.nix -- it has already built.
      #
      # `extra-` rather than plain `substituters`: the latter replaces the
      # list, and quietly dropping cache.nixos.org would look like a slow
      # network rather than a config error.
      #
      # Not on the desktop itself, which would be asking a service on this
      # machine for paths this machine already has -- and would block on the
      # connect timeout whenever tailscale is down.
      extra-substituters = lib.optional (
        config.networking.hostName != "nixos-desktop"
      ) "http://nixos-desktop:5000";
      extra-trusted-public-keys = lib.optional (
        config.networking.hostName != "nixos-desktop"
      ) "nixos-desktop-1:YsdpYxRpYwHAN8WFWJhTU9kC1QWc4OqacfZaPfe/ey8=";
      # A laptop away from the tailnet must fall through to cache.nixos.org
      # rather than stall on every path. Without these two a substituter that
      # is merely unreachable turns a rebuild into a source build.
      connect-timeout = 5;
      fallback = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Store deduplication is handled by the weekly nix.optimise timer below;
      # auto-optimise-store would additionally hash every path on every build.
      # Root-equivalent, not a convenience list: the daemon runs as root and
      # honours settings a trusted client sends it, so a trusted user can point
      # it at their own substituter and signing key, or weaken build isolation
      # until a derivation's builder runs unsandboxed as root. It routes around
      # `security.sudo.enable = false` and the local/active polkit guard alike.
      #
      # codebam is already in wheel on their own workstation, so this grants
      # nothing new. `makano` used to be added on the desktop and is not any
      # more — that account has three authorized SSH keys on machines we do not
      # administer, which made every one of them a root key for this host.
      # Anything that needs a cache belongs in substituters/trusted-public-keys
      # system-wide instead of here.
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
      # No GCS substituter. services.gcp-builder is off by default and no
      # longer fills a bucket; add both the URL and its public key here if a
      # reader is wanted again. A URL without the key rejects every narinfo
      # as unsigned, which looks exactly like an empty cache.
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
