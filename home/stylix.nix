{ pkgs, ... }:

{
  stylix = {
    enable = true;

    targets = {
      mangohud.enable = false;
      librewolf = {
        profileNames = [ "codebam" ];
      };
      nushell.enable = false;
      fish.enable = false;
      neovide.enable = false;
    };

    polarity = "dark";
    image = builtins.fetchurl {
      url = "https://w.wallhaven.cc/full/2y/wallhaven-2y2wg6.png";
      sha256 = "sha256-nFoNfk7Y/CGKWtscOE5GOxshI5eFmppWvhxHzOJ6mCA=";
    };
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };

      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
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
