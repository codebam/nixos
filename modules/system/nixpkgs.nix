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
        (_: prev: {
          # Here rather than in the module that installs it, because the
          # keybinding that runs it lives in home-manager and both sides have
          # to name the same derivation. `useGlobalPkgs` is what makes that
          # work. CPU whisper.cpp, which is the build the binary cache has; a
          # host wanting the Vulkan one asks with `voiceToText.gpu` and gets an
          # override of this rather than a second overlay entry.
          voice-to-text = prev.callPackage ../../pkgs/voice-to-text.nix { };

          # The streaming variant, for the same reason and by the same route.
          # A separate derivation rather than a flag on the one above: the two
          # share only a model, and a host can bind either without the other
          # deciding what `voice-to-text` means.
          voice-to-text-stream = prev.callPackage ../../pkgs/voice-to-text-stream.nix { };

          # Same reason as the two above: home-manager both installs this and
          # names it in a tmux popup binding, and a second `callPackage` on
          # each side would be two derivations that happen to agree.
          agent-overview = prev.callPackage ../../pkgs/agent-overview.nix { };

          # Vendor ships a prebuilt Wails + WebKitGTK tarball, no nixpkgs
          # package. Overlay so home-manager and systemPackages name one
          # derivation (useGlobalPkgs).
          sigmashake-desktop = prev.callPackage ../../pkgs/sigmashake-desktop.nix { };

          # Two things are wrong with nixpkgs' own `whisper-cpp-vulkan` here.
          #
          # It declares vulkan-headers and vulkan-loader, and 1.8.7's
          # ggml-vulkan.cpp also includes <spirv/unified1/spirv.hpp>, which is
          # in neither -- it is spirv-headers, which nothing pulls in. The
          # include is written as an `__has_include` chain ending in a
          # deliberate hard error, so the build gets to 55% and then stops on
          # "file not found".
          #
          # And `rocmSupport` is on for this desktop, which makes the same
          # derivation set CMAKE_CXX_COMPILER to hipcc -- so the Vulkan sources
          # compile as HIP, for all sixteen AMDGPU targets, to produce a
          # backend that talks to Vulkan anyway. Turning it off for this build
          # is not losing a backend: GGML_HIPBLAS is the pre-0.15 spelling and
          # ggml ignores it, which is why the rocm-enabled `whisper-cpp` in
          # this closure ships CPU backends and nothing else.
          whisper-cpp-vulkan =
            (prev.whisper-cpp.override {
              vulkanSupport = true;
              rocmSupport = false;
            }).overrideAttrs
              (old: {
                buildInputs = old.buildInputs ++ [ prev.spirv-headers ];
              });
          # yt-dlp needs a JS runtime to solve YouTube's nsig challenge, and
          # nixpkgs defaults `jsRuntime` to deno -- 251 MB, pulled into this
          # closure transitively by mpv. quickjs-ng runs the same extractor
          # code in a few MB. Do not swap this for `javascriptSupport =
          # false`: that drops the runtime entirely and YouTube playback in
          # mpv fails on any nsig-protected video.
          yt-dlp = prev.yt-dlp.override { jsRuntime = prev.quickjs-ng; };

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
