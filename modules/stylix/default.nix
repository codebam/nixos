{ pkgs, ... }:
{
  stylix = {
    enable = true;
    autoEnable = false;
    polarity = "dark";
    targets = {
      console.enable = false;
      fish.enable = false;
      gnome.enable = true;
      gtk.enable = false;
      qt.enable = false;
    };
    # Dragon, not wave: base00 is a hue-neutral near-black (#181616 instead
    # of #1f1f28), so translucent terminal glass tints the synthwave wallpaper
    # dark rather than blue-grey.
    base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa-dragon.yaml";
    # Neon McLaren mural (wallhaven j5pr65, its native 3840x2160 scaled to
    # 2560x1440 exactly). One screen, not a panorama: the shell paints the
    # same picture on each output's own desktop, so DP-1 and DP-3 mirror it
    # and 5120x1440 "joined" art only shows its centre half, twice. Measured
    # 12.8% mean drive with `bake.mjs verify` (9% of pixels over half drive,
    # peak 1.0) -- over the oled budget (README: <8%) and ~2x the synthwave
    # mural it replaces, the price of the neon highlights. synthwave-hype.png
    # and the NixOS catppuccin artwork stay in wallpapers/ to switch back to.
    # base16Scheme above is pinned, so this changes the wallpaper only.
    image = ../../wallpapers/neon-mclaren.png;
    # capitaine rather than bibata or phinger: bibata-cursors builds every
    # colour variant into one 338 MB output and there is no attribute for a
    # single theme, and phinger is 53 MB. This is ~10 MB for the same set of
    # shapes ("capitaine-cursors-white" is the light variant).
    cursor = {
      package = pkgs.capitaine-cursors;
      name = "capitaine-cursors";
      size = 32;
    };
    icons = {
      package = pkgs.papirus-icon-theme;
      light = "Papirus Light";
      dark = "Papirus Dark";
    };
    fonts = {
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
