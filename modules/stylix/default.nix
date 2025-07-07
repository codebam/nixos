{ pkgs, ... }:
{
  stylix = {
    enable = true;
    polarity = "dark";
    targets = {
      chromium.enable = false;
      console.enable = false;
      feh.enable = false;
      fish.enable = false;
      glance.enable = false;
      gnome.enable = true;
      grub.enable = false;
      gtk.enable = true;
      kmscon.enable = false;
      lightdm.enable = false;
      nixvim.enable = false;
      nvf.enable = false;
      plymouth.enable = false;
      qt.enable = true;
      regreet.enable = false;
      spicetify.enable = false;
    };
    base16Scheme = "${pkgs.base16-schemes}/share/themes/ayu-dark.yaml";
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
        name = "Fira Code NerdFont";
      };
      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
