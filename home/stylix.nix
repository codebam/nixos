{ pkgs, ... }:

{
  stylix = {
    enable = true;

    targets = {
      librewolf = {
        profileNames = [ "codebam" ];
      };
      foot.enable = true;
      gtk.enable = true;
      mako.enable = true;
      qt.enable = false;
      sway.enable = true;
      swaylock.enable = true;
      tmux.enable = true;
      fish.enable = false;
    };

    polarity = "dark";
    image = ../wallpaper.png;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/ayu-dark.yaml";
    fonts = {
      sizes = {
        desktop = 14;
        terminal = 14;
      };

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
