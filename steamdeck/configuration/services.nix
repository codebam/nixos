{ lib, ... }:

{
  services = {
    # Plasma is the session "Switch to Desktop" launches (jovian.nix), so
    # the module has to be on; viewport (viewport.nix) and sway remain
    # installed as alternative sessions. Boot default is unchanged: Jovian
    # still autostarts Gaming Mode.
    desktopManager.plasma6.enable = true;
    # plasma6.nix sets this with mkDefault; same choice as the desktop
    # (desktop/configuration/plasma.nix), for the same closure reason.
    orca.enable = false;
    # scx/scx_lavd config comes from modules/services/default.nix, which is
    # off; only the desktop opts in through the main-snapshot overlay in
    # modules/system/nixpkgs.nix. The plain false there also keeps Jovian's
    # mkDefault true from turning scx on here.
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
    # The Deck has no suspend or hibernate key: the only power intent is the
    # physical button (KEY_POWER), handled by the power-button daemon. But
    # something synthetic sent phantom KEY_SUSPEND/KEY_HIBERNATE presses into
    # logind during desktop use -- "Suspend key pressed short" in the journal
    # with nobody touching the deck -- and the session went to sleep and woke
    # as a dead black screen. Ignore both keys outright so no input device,
    # real or virtual, can sleep this machine that way again.
    logind.settings.Login = {
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
    };
  };

  # Plasma's module turns the KDE PIM suite on by default -- akonadi, KMail
  # and Kontact, with akonadi autostarting in the session. Same choice as the
  # desktop (desktop/configuration/plasma.nix): a handheld session does not
  # need it.
  programs.kde-pim.enable = false;
}
