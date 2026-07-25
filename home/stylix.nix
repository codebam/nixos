_:

{
  # Scheme, wallpaper, cursor, icons and font *families* all come from the
  # system module (modules/stylix/default.nix) -- stylix's NixOS module feeds
  # them to every home-manager user, so repeating them here only created two
  # places to edit. What stays is what genuinely differs per user: which
  # targets are themed, and the desktop/terminal font sizes.
  stylix = {
    enable = true;
    autoEnable = false;

    targets = {
      librewolf = {
        profileNames = [ "codebam" ];
      };
      foot.enable = true;
      kitty.enable = true;
      ghostty.enable = true;
      gtk.enable = false;
      swaync.enable = true;
      qt.enable = false;
      sway.enable = false;
      swaylock.enable = true;
      tmux.enable = true;
      fish.enable = false;
      mangohud.enable = false;
    };

    fonts.sizes = {
      desktop = 14;
      terminal = 14;
    };
  };
}
