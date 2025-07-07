{ pkgs, ... }:

{
  stylix = {
    enable = true;

    targets = {
      librewolf = {
        profileNames = [ "codebam" ];
      };
      avizo.enable = false;
      bat.enable = false;
      bemenu.enable = false;
      bspwm.enable = false;
      btop.enable = false;
      cava.enable = false;
      cavalier.enable = false;
      dunst.enable = false;
      emacs.enable = false;
      eog.enable = false;
      fcitx5.enable = false;
      feh.enable = false;
      firefox.enable = false;
      fish.enable = false;
      fnott.enable = false;
      foliate.enable = false;
      foot.enable = true;
      forge.enable = false;
      fuzzel.enable = false;
      fzf.enable = false;
      gedit.enable = false;
      ghostty.enable = false;
      gitui.enable = false;
      glance.enable = false;
      gnome.enable = false;
      gnome-text-editor.enable = false;
      gtk.enable = true;
      halloy.enable = false;
      helix.enable = false;
      hyprland.enable = false;
      hyprlock.enable = false;
      hyprpaper.enable = false;
      i3.enable = false;
      k9s.enable = false;
      kde.enable = false;
      kitty.enable = false;
      kubecolor.enable = false;
      lazygit.enable = false;
      mako.enable = true;
      mangohud.enable = false;
      micro.enable = false;
      mpv.enable = false;
      ncspot.enable = false;
      neovim.enable = false;
      nixvim.enable = false;
      nushell.enable = false;
      nvf.enable = false;
      qt.enable = true;
      qutebrowser.enable = false;
      rio.enable = false;
      river.enable = false;
      rofi.enable = false;
      spicetify.enable = false;
      spotify-player.enable = false;
      starship.enable = false;
      sway.enable = true;
      swaylock.enable = true;
      swaync.enable = false;
      sxiv.enable = false;
      tmux.enable = true;
      tofi.enable = false;
      vim.enable = false;
      vscode.enable = false;
      waybar.enable = false;
      wayfire.enable = false;
      wayprompt.enable = false;
      wezterm.enable = false;
      wob.enable = false;
      wofi.enable = false;
      wpaperd.enable = false;
      xfce.enable = false;
      xresources.enable = false;
      yazi.enable = false;
      zathura.enable = false;
      zed.enable = false;
      zellij.enable = false;
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
