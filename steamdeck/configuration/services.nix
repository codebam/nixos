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
    # The shared module leaves scx-loader off with a plain false; opt the
    # Deck in so it uses the game-tuned cake from the main snapshot pinned in
    # modules/system/nixpkgs.nix. Jovian's own scx unit is disabled below --
    # two schedulers cannot both own sched_ext's root/ops.
    scx-loader.enable = lib.mkForce true;
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

  # Jovian's steam module starts its own scx_lavd from jovianPackages.scx-scheds,
  # gated on /sys/kernel/sched_ext. With scx-loader enabled above it would
  # compete for the sched_ext root, so turn the vendor unit off. mkForce is
  # needed because Jovian sets enable = true as a plain value.
  systemd.services.scx.enable = lib.mkForce false;

  # Plasma's module turns the KDE PIM suite on by default -- akonadi, KMail
  # and Kontact, with akonadi autostarting in the session. Same choice as the
  # desktop (desktop/configuration/plasma.nix): a handheld session does not
  # need it.
  programs.kde-pim.enable = false;
}
