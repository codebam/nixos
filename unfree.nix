# Unfree package names this flake is willing to build. Defined once and read by
# both the NixOS hosts (modules/system/nixpkgs.nix, via the `unfreePackages`
# option) and the flake's `packages` output, so the two cannot disagree about
# what is allowed. Keep sorted.
[
  "claude-code"
  "google-chrome"
  "google-chrome-unstable"
  "libretro-fbneo"
  "libretro-genesis-plus-gx"
  "libretro-mame2000"
  "libretro-mame2003"
  "libretro-mame2015"
  "libretro-snes9x"
  "polariumcode"
  "rpcs3"
  "sigmashake-desktop"
  "ssg"
  "steam"
  "steam-jupiter-unwrapped"
  "steam-original"
  "steam-run"
  "steam-unwrapped"
  "steamdeck-hw-theme"
  "steamcmd"
]
