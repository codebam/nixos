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
        sway-unwrapped = inputs.sway.packages.${prev.system}.default.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (prev.fetchpatch {
              name = "hdr10.patch";
              url = "https://github.com/swaywm/sway/compare/master..emersion:hdr10.patch";
              hash = "sha256-t57uUw++faJODxhgcprA9nkRWYUelqyd1yJu7afp5hc=";
            })
            ../sway-patches/sway-hdr.patch
            ../sway-patches/load-configuration-from-etc.patch
            (prev.replaceVars ../sway-patches/fix-paths.patch {
              inherit (prev) swaybg;
            })
            ../sway-patches/sway-config-nixos-paths.patch
          ];
        });
      })
    ];
  };
}
