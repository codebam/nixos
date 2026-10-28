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
          (import ../../pkgs {
            pkgs = final;
            inherit prev;
          })
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

            # scx_lavd 1.1.3 regressed on kernel 7.2 (a migration-disabled
            # task affine to one CPU was never dispatched and sat out the RCU
            # stall timeout); nixpkgs had reverted to 1.1.2, which is why this
            # pin exists. nixpkgs now carries 1.1.4, which contains the fix
            # (upstream 6d31ddd8973), so master is tracked here only for the
            # scx_lavd work that landed after that tag: per-compute-domain
            # idle tracking, the uclamp/perf-target fix and the load-balance
            # band cap. Pin by commit, not branch, so this rebuilds
            # identically; importCargoLock reads the matching Cargo.lock
            # instead of a cargoHash, so no tag hash can drift onto a
            # different dependency set. Drop this attr to fall back to
            # nixpkgs' 1.1.4 if master breaks.
            scx =
              let
                rustscheds = prev.scx.rustscheds.overrideAttrs (old: {
                  version = "1.1.4-unstable-2026-10-27";
                  src = prev.fetchFromGitHub {
                    owner = "sched-ext";
                    repo = "scx";
                    rev = "abcc603de96a0809e74b4b266eea8e16419be567";
                    hash = "sha256-DCIz7/slDJmw6MYZ7zm+y3AbStKxFfUcKTQlB5pNAO0=";
                  };
                  cargoDeps = prev.rustPlatform.importCargoLock {
                    lockFileContents = builtins.readFile (
                      builtins.fetchurl {
                        url = "https://raw.githubusercontent.com/sched-ext/scx/abcc603de96a0809e74b4b266eea8e16419be567/Cargo.lock";
                        sha256 = "b922551e6a76c0480c41a488a27c4cbcf12588aa31a44841183bf2525cf0e8f1";
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

            # nyx's `helix_git` builds its grammar farm from languages.json,
            # straight from each grammar's pinned revision. Its tree-sitter-perl
            # pin (72a08a49, 2024-10-07) predates upstream's bsearch fix
            # (18d659f9, which moved the vendored bsearch into a header) and its
            # src/bsearch.c does not compile against glibc 2.44's C23
            # declarations ("expected identifier or '(' before '_Generic'").
            # nixpkgs patches the same revision the same way inside its own
            # helix package; nyx's separate build path misses it, and the whole
            # home closure -- including the desktop's nightly auto-upgrade --
            # stops on this one grammar. Delete this once the languages.json
            # pin moves past 18d659f9.
            tree-sitter = prev.tree-sitter // {
              buildGrammar =
                args:
                let
                  drv = prev.tree-sitter.buildGrammar args;
                in
                if (args.language or "") == "perl" then
                  drv.overrideAttrs (old: {
                    postPatch = ''
                      ${old.postPatch or ""}
                      if [ -e src/bsearch.c ]; then
                        rm src/bsearch.c
                        substituteInPlace src/tsp_unicode.h \
                          --replace-fail '#include "bsearch.c"' ""
                      fi
                    '';
                  })
                else
                  drv;
            };
          }
        )
      ];
    };
  };
}
