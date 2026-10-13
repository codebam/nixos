{ lib, ... }:

{
  services = {
    # jovian turns plasma6 on; viewport is the session here (see viewport.nix).
    desktopManager.plasma6.enable = lib.mkForce false;
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
}
