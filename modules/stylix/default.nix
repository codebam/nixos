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
    # Nebula/ember frame from the OLED pool (wallpapers/oled/, 5120x1440,
    # generated from live.html -- the pool is the one place wallpaper art is
    # authored now). Picked over the neon-mclaren mural it replaces on the
    # exposure numbers, not on looks: mclaren measured 12.8% mean drive, 9%
    # of pixels over half drive and a peak of 1.0 -- three times the budget
    # this file exists to keep. This frame is 1.14% mean drive, nothing over
    # half drive, peak 0.68.
    #
    # One screen, not a panorama: the shell paints the same picture on each
    # output's own desktop, so DP-1 and DP-3 mirror it. `fill` therefore keeps
    # the centre 2560 columns of the 5120-wide frame on each monitor -- the
    # measured crop is 0.95% drive and 0.9% over 25% grey, so the crop is not
    # hiding a bright half. Art authored for a joined surface would do that.
    #
    # neon-mclaren.png, synthwave-hype.png and the NixOS catppuccin artwork
    # stay in wallpapers/ to switch back to. base16Scheme above is pinned, so
    # this changes the wallpaper only.
    image = ../../wallpapers/oled/pool/02-nebula-ember.webp;
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
