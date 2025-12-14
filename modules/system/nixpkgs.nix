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
            rev = "ba931024a514be75a8a84a21483f9a888e0a9f1c";
            hash = "sha256-vNsnDWQJ7044FLBIYAjEtONQXJAn/6yDC24Hg3lXhko=";
          };
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "f4aba22582184c9a4a20fd7a9ffd70c63b4b393d";
            hash = "sha256-2k4M3H5E4+9QVR7uV2+R834fiA8vFNjUSDEZpR0fM/I=";
          };
          # patches = old.patches ++ [
          #   (prev.fetchurl {
          #     url = "https://github.com/swaywm/sway/compare/master..emersion:hdr10.patch";
          #     hash = "sha256-wekk6bXwiSL0VCgJGEXuiMUGv9MxjG/8JmDfHlMtBMo=";
          #   })
          # ];
        });
      })
    ];
  };
}
