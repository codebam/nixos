{
  lib,
  config,
  ...
}:
{
  # The list itself lives in unfree.nix at the repo root, shared with the
  # flake's `packages` output so the two cannot disagree about what is allowed.
  # The binary cache uploader reads this option and must not push any of them
  # to a public bucket.
  options.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = import ../../pkgs/unfree.nix;
    description = "Unfree package names this system is allowed to build.";
  };

  config = {
    nixpkgs = {
      config = {
        # checkMeta = true;
        # showDerivationWarnings = [ "maintainerless" ];
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.unfreePackages;
      };
      overlays = [
        # Local derivations are defined once in pkgs/default.nix, shared with
        # the flake's `packages` output. Installing them here as well means
        # home-manager (useGlobalPkgs) and the system name the same store
        # paths.
        (
          final: prev:
          (import ../../pkgs { pkgs = final; })
          // {
            # yt-dlp needs a JS runtime to solve YouTube's nsig challenge, and
            # nixpkgs defaults `jsRuntime` to deno -- 251 MB, pulled into this
            # closure transitively by mpv. quickjs-ng runs the same extractor
            # code in a few MB. Do not swap this for `javascriptSupport =
            # false`: that drops the runtime entirely and YouTube playback in
            # mpv fails on any nsig-protected video.
            yt-dlp = prev.yt-dlp.override { jsRuntime = prev.quickjs-ng; };

            # Prebuilt Electron instead of source builds: upstream binaries
            # are trusted here to avoid compiling Chromium per Electron
            # major. Revisit if reproducibility of the desktop closure
            # matters more than the build time this saves.
            electron = prev.electron-bin;
            electron-unwrapped = prev.electron-bin;
            electron_41 = prev.electron_41-bin;
            electron_40 = prev.electron_40-bin;
            xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (oldAttrs: {
              buildInputs = oldAttrs.buildInputs ++ [ prev.wmenu ];
              postInstall = ''
                ${oldAttrs.postInstall or ""}
                wrapProgram $out/libexec/xdg-desktop-portal-wlr \
                  --prefix PATH : ${lib.makeBinPath [ prev.wmenu ]}
              '';
            });

            # scx_lavd 1.1.3 regressed on kernel 7.2 and nixpkgs reverted to
            # 1.1.2; the fix (upstream 6d31ddd8973) only exists on main. Pin
            # a main snapshot that carries it by commit, not branch, so this
            # rebuilds identically. importCargoLock reads the matching
            # Cargo.lock instead of a cargoHash, so the 1.1.3 git tag's hash
            # cannot silently drift onto a different dependency set.
            scx =
              let
                rustscheds = prev.scx.rustscheds.overrideAttrs (old: {
                  version = "1.1.3-unstable-2026-09-11";
                  src = prev.fetchFromGitHub {
                    owner = "sched-ext";
                    repo = "scx";
                    rev = "8b2479571c0768310510c061960d2c40cb64d160";
                    hash = "sha256-/bRCnsZ0d56WuIcBNrXmpykS8CoLqkjeKJgekIpbTgQ=";
                  };
                  cargoDeps = prev.rustPlatform.importCargoLock {
                    lockFileContents = builtins.readFile (
                      builtins.fetchurl {
                        url = "https://raw.githubusercontent.com/sched-ext/scx/8b2479571c0768310510c061960d2c40cb64d160/Cargo.lock";
                        sha256 = "127bd3d568cdeb31ea660d811bb1f2f3617aad9bb60d889cc71c0f4486d95816";
                      }
                    );
                  };
                  # Only the desktop's scheduler is shipped, so there is no
                  # reason to compile the other twenty-odd workspace bins on
                  # every nixpkgs bump.
                  env = (old.env or { }) // {
                    cargoBuildFlags = "--package scx_lavd";
                  };
                  postInstall = "";
                  passthru = (old.passthru or { }) // {
                    schedulers = [ "scx_lavd" ];
                  };
                  __intentionallyOverridingVersion = true;
                });
                base = prev.scx // {
                  inherit rustscheds;
                };
              in
              base
              // {
                full = prev.scx.full.override { scx = base; };
              };
          }
        )
      ];
    };
  };
}
