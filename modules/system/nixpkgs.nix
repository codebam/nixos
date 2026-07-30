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
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) config.unfreePackages;
    };
    overlays = [
      (_: prev: {
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
