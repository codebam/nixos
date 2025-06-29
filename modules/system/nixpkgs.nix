{ lib
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
        ];
    };
    overlays = [
      (final: prev: {
        # inherit (inputs.ollama.legacyPackages.${prev.system}) ollama;
        wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            rev = "f5e7caf59994cfa08650cade41374e23779a24a4";
            hash = "sha256-h4yl6USEm4jQKknBu5LXTmjkJVfMeC5xz/xI6M8hy08=";
          };
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "c2f08075ec00632293bbc63582c7f3ffd75441af";
            hash = "sha256-kwDv9TP3oIxfk7x8zRFzSiecTKPqZwDg+AA9cdeDXCg=";
          };
          patches = old.patches ++ [
            (prev.fetchurl {
              url = "https://github.com/swaywm/sway/compare/master..emersion:hdr10.patch";
              hash = "sha256-7QesKqsk/oR56KNCr276afGc52VZhlDNL9qcK979a+M=";
            })
            ../sway-patches/sway-hdr.patch
          ];
        });
      })
    ];
  };
}
