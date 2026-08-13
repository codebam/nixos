{ config, pkgs, ... }:

# The signing key lives in secrets/secrets.yaml as `nix-serve-key`, and the
# matching public key is committed in modules/system/nix.nix. The two are a
# pair: regenerate one and the other has to change with it, or the laptop and
# Deck reject every narinfo this serves as unsigned -- which fails silently and
# looks exactly like a cache with nothing in it. To rotate:
#
#   nix-store --generate-binary-cache-key nixos-desktop-1 priv.pem pub.pem
#   sops set secrets/secrets.yaml '["nix-serve-key"]' "$(jq -Rs . < priv.pem)"
#   # then paste pub.pem into extra-trusted-public-keys in nix.nix
#
# Note that sops-nix validates secret *names* at build time, not activation:
# renaming the key here without renaming it there breaks `nixos-rebuild` and
# `nix flake check` on this host outright, rather than failing at switch.
#
# A binary cache over the tailnet, served straight out of this machine's
# /nix/store.
#
# Three hosts share one flake and one `modules/` tree, so nixos-laptop and
# nixos-steamdeck build a closure that is largely identical to the one the
# desktop has already built -- and where it differs, it differs in exactly the
# packages nixpkgs' own cache does not have: the chaotic `_git` builds
# (helix_git, mangohud_git, gamescope_git, firefox_nightly), the
# viewport-smithay flake, and every local override in modules/system/nixpkgs.nix. Those are
# what the laptop was compiling from source.
#
# nix-serve-ng rather than nix-serve: same interface, same options, a Haskell
# rewrite that does not fork a `nix-store` process per narinfo request.
#
# What this deliberately is NOT: durable storage. There is no separate store
# here, so the cache holds exactly what this machine's store holds -- run
# `nh clean` (or the weekly timer) and the paths it collected are gone from
# the cache too. That is the trade for zero extra disk and zero push step; if
# retention ever matters, attic is the thing to switch to, not a tweak here.
{
  services.nix-serve = {
    enable = true;
    package = pkgs.nix-serve-ng;
    port = 5000;

    # 0.0.0.0, and the firewall is the boundary rather than the bind address:
    # 5000 is not in networking.nix's allowedTCPPorts, so the WAN cannot reach
    # it, while tailscale0 is in firewall.trustedInterfaces and accepts
    # everything. That is the intent -- the tailnet is who this serves.
    #
    # Note what that means, since the same reasoning went the other way for
    # ollama: every device on the tailnet can read any path in this store,
    # unauthenticated. For a binary cache that is the feature. It is safe here
    # only because sops secrets are decrypted to /run, never into the store --
    # anything that does land in the store is world-readable to the tailnet
    # from now on.
    bindAddress = "0.0.0.0";

    # Clients reject unsigned narinfos unless they set require-sigs = false,
    # which would also let them accept anything else unsigned. Sign instead.
    secretKeyFile = config.sops.secrets.nix-serve-key.path;
  };

  # Root-owned, default mode, deliberately: the unit runs DynamicUser = true,
  # so there is no static `nix-serve` account for sops to chown to and naming
  # one fails activation. It does not need one -- the module passes the key in
  # as `LoadCredential=NIX_SECRET_KEY_FILE`, which systemd reads as root and
  # hands to the service through its credentials directory after the drop.
  sops.secrets.nix-serve-key = { };
}
