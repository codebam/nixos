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
            rev = "25bec59c75e7f6c95d29686915d1ddd0c62ab539";
            hash = "sha256-49w42Z9CcdfnPwfVer+CzGe0qen7KRsf/n5ExzbeTag=";
          };
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "fa497964fd55632beacf5f425e964ae4893e25b9";
            hash = "sha256-J6YGDIdQFCADLtoGSK7ZewJYGdVgxMbmPYcRm3zIuCg=";
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
