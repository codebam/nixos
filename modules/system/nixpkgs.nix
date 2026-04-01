{ lib
, inputs
, config
, ...
}:
{
  nixpkgs = {
    config = {
      # checkMeta = true;
      # showDerivationWarnings = [ "maintainerless" ];
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "android-studio"
          "android-sdk-platform-tools"
          "steam"
          "steam-original"
          "steam-run"
          "steam-unwrapped"
          "open-webui"
          "discord"
          "discord-ptb"
          "discord-canary"
          "steamdeck-hw-theme"
          "steam-jupiter-unwrapped"
          "libretro-genesis-plus-gx"
          "libretro-snes9x"
          "libretro-fbneo"
          "libretro-mame2000"
          "libretro-mame2003"
          "libretro-mame2015"
          "vscode"
          "via"
          "claude-code"
          "google-cloud-sdk"
          "google-chrome"
          "google-chrome-unstable"
          "antigravity"
          "cuda_nvcc"
        ];
    };
    overlays = [
      (final: prev: {
        xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (oldAttrs: {
          nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ prev.makeWrapper ];
          buildInputs = oldAttrs.buildInputs ++ [ prev.wmenu ];
          postInstall = ''
            ${oldAttrs.postInstall or ""}
            wrapProgram $out/libexec/xdg-desktop-portal-wlr \
              --prefix PATH : ${lib.makeBinPath [ prev.wmenu ]}
          '';
        });
        wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
          pname = "wlroots";
          version = "0.21.0-dev";
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            rev = "e22084f63967aa72cb56873aeb48b01fb8dc2c9b";
            hash = "sha256-6eOqeq9yYeY815rad1Pw2XhF1Y/eee9HwWlCNVZpfFo=";
          };
          mesonFlags = builtins.filter (opt: !prev.lib.hasInfix "xwayland" opt) old.mesonFlags;
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "909a2ddb5fff528e735341529a028d2ef21836db";
            hash = "sha256-Qjz4XGiggSj6kg6GXMMPl4JYE8yYy1byvNNBvvXnuZI=";
          };
        });
        android-tools = prev.androidenv.androidPkgs.platform-tools.overrideAttrs (oldAttrs: rec {
          version = "36.0.0";
          src = prev.fetchurl {
            url = "https://dl.google.com/android/repository/platform-tools_r${version}-linux.zip";
            sha256 = "sha256-Dq1kLJQ//nlwH8zKj18cacTOT0PfLu/uVT9syyfL++g=";
          };
        });
      })
    ];
  };
}
