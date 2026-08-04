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
      "android-sdk-platform-tools"
      "android-studio"
      "antigravity"
      "antigravity-cli"
      "antigravity-ide"
      "claude-code"
      "cuda_nvcc"
      "discord"
      "discord-canary"
      "discord-ptb"
      "firefox-bin"
      "firefox-bin-unwrapped"
      "google-chrome"
      "google-chrome-unstable"
      "google-cloud-sdk"
      "libretro-fbneo"
      "libretro-genesis-plus-gx"
      "libretro-mame2000"
      "libretro-mame2003"
      "libretro-mame2015"
      "libretro-snes9x"
      "mongodb"
      "open-webui"
      "rpcs3"
      "steam"
      "steam-jupiter-unwrapped"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
      "steamdeck-hw-theme"
      "steamcmd"
      "via"
      "vscode"
      "warp-terminal"
    ];
    description = "Unfree package names this system is allowed to build.";
  };

  config = {
    nixpkgs = {
      config = {
        # checkMeta = true;
        # showDerivationWarnings = [ "maintainerless" ];
        permittedInsecurePackages = [
          "pnpm-9.15.9"
        ];
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
