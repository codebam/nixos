{
  lib,
  config,
  ...
}:
{
  # Named once, read twice: by allowUnfreePredicate below, and by the binary
  # cache uploader, which must not push any of them to a public bucket.
  options.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "antigravity"
      "antigravity-cli"
      "antigravity-ide"
      "claude-code"
      "google-chrome"
      "google-chrome-unstable"
      "google-cloud-sdk"
      "libretro-fbneo"
      "libretro-genesis-plus-gx"
      "libretro-mame2000"
      "libretro-mame2003"
      "libretro-mame2015"
      "libretro-snes9x"
      "rpcs3"
      "sigmashake-desktop"
      "ssg"
      "steam"
      "steam-jupiter-unwrapped"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
      "steamdeck-hw-theme"
      "steamcmd"
    ];
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
        (final: prev: {
          # Home-manager both installs this and names it in a tmux popup
          # binding. Keeping it in the shared overlay makes both uses resolve
          # to the same derivation.
          agent-overview = prev.callPackage ../../pkgs/agent-overview.nix { };

          # Vendor ships a prebuilt Wails + WebKitGTK tarball, no nixpkgs
          # package. Overlay so home-manager and systemPackages name one
          # derivation (useGlobalPkgs). Not installed right now; the CLI is.
          sigmashake-desktop = prev.callPackage ../../pkgs/sigmashake-desktop.nix { };

          # Named by both the system gnupg.agent and codebam's home-manager
          # one, and `pinentry-program` in gpg-agent.conf is a path -- two
          # callPackages would be two paths for the same wrapper.
          pinentry-auto = prev.callPackage ../../pkgs/pinentry-auto.nix {
            terminal = final.rio;
          };

          # Official CLI from https://sigmashake.com/install (static Go binary).
          ssg = prev.callPackage ../../pkgs/ssg.nix { };

          # Zero-dependency C++23 CLI + MCP server that hands coding agents a
          # ranked, deterministic call-graph map of a repo. All deps vendored
          # in-tree, so the build needs no network; the binary installs with
          # `--component ripwire` and skills/ + hooks/ are staged under
          # share/ripwire (v0.3.8's CMake predates upstream's own asset
          # install rules), mirroring the upstream install.sh layout.
          ripwire = prev.callPackage ../../pkgs/ripwire.nix { };

          # npm CLI (@zvec/zvec-grep) with no nixpkgs package. The registry
          # tarball ships a prebuilt dist/ but no lockfile, so the derivation
          # pins the upstream tag's package-lock.json and skips install
          # scripts; every native dependency (zvec, onnxruntime, ripgrep,
          # llama.cpp, sharp) arrives as a prebuilt platform package.
          zvec-grep = prev.callPackage ../../pkgs/zvec-grep.nix { };

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
        })
      ];
    };
  };
}
