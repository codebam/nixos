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
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            rev = "1ce992d7cb5023a7a7c91ed6ce156529e3709657";
            hash = "sha256-2iVbJK4i37DIsTCy8cGsjsVoJobJe5kfGa1VCe9bmmQ=";
          };
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "c57daaf0d1640b45579d75ce9775b8c0d03299b7";
            hash = "sha256-zP+cgC/sv5hxcH50z5h0nji1YEMEpQfZUR3n3OrN1nY=";
          };
          # patches = old.patches ++ [
          #   (prev.fetchurl {
          #     url = "https://github.com/swaywm/sway/compare/master..emersion:hdr10.patch";
          #     hash = "sha256-wekk6bXwiSL0VCgJGEXuiMUGv9MxjG/8JmDfHlMtBMo=";
          #   })
          # ];
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
