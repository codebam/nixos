{ pkgs, ... }:
{
  programs = {
    nix-index = {
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
    # Paired with users.users.codebam.shell = pkgs.nushell.
    nushell = {
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
    # that user this block is shadowed. Change home/services.nix, not this,
    # when adjusting codebam's agent.
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-auto;
    };
    sway.enable = true;
    dconf.enable = true;
  };

  # programs.nushell does not add itself to /etc/shells the way the fish
  # and bash modules do; without this the login shell configured in
  # modules/users/default.nix is not listed there.
  environment.shells = [ pkgs.nushell ];
}
