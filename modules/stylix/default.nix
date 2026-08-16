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
    base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa.yaml";
    image = ../../wallpaper.png;
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
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
