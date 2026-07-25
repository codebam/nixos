{ pkgs, ... }:
{
  programs = {
    nix-index = {
      enable = true;
    };
    ccache = {
      enable = true;
    };
    uwsm = {
      enable = true;
      waylandCompositors = {
        sway = {
          prettyName = "Sway";
          comment = "Sway compositor managed by UWSM";
          binPath = "/run/current-system/sw/bin/sway";
        };
      };
    };
    fish = {
      enable = true;
    };
    nix-index-database.comma.enable = true;
    nix-ld.enable = true;
    wireshark = {
      enable = true;
      usbmon.enable = true;
      package = pkgs.wireshark;
    };
    # This covers users without a home-manager gpg-agent (makano). codebam's
    # home-manager services.gpg-agent writes the same units into
    # ~/.config/systemd/user, which wins the user-unit search path -- so for
    # that user this block is shadowed and pinentry-gnome3 is what runs. Change
    # home/services.nix, not this, when adjusting codebam's agent.
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-tty;
    };
    sway.enable = true;
    dconf.enable = true;
  };
}
