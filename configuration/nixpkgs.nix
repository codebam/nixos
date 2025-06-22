{ lib
, pkgs
, inputs
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
        ];
    };
    overlays = [
      (final: prev: {
        inherit (inputs.linux-firmware.legacyPackages.${prev.system}) linux-firmware;
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
            rev = "170c9c9525f54e8c1ba03847d5f9b01fc24b8c89";
            hash = "sha256-ziKsVin8Ze00ZkI4c6TL9sZgNCkdnow75KXixkuhCpM=";
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
