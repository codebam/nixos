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
    default = import ../../unfree.nix;
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
          }
        )
      ];
    };
  };
}
