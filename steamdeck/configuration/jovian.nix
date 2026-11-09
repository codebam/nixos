_:

{
  jovian = {
    decky-loader = {
      enable = false;
      user = "codebam";
      stateDir = "/home/codebam/.config/decky-loader";
    };
    steam = {
      enable = true;
      user = "codebam";
      autoStart = true;
      # "Switch to Desktop" launches Plasma: jovian's setup unit runs
      # `steamosctl set-default-desktop-session ${desktopSession}.desktop`,
      # and the value is validated against the session names this system
      # provides. Plasma comes from services.desktopManager.plasma6.enable
      # (services.nix); viewport (viewport.nix) and sway stay installed so
      # SDDM can still pick them by hand. Gaming Mode is still what boots:
      # autoStart above is untouched.
      desktopSession = "plasma";
    };
    devices = {
      steamdeck = {
        enable = true;
      };
    };
    steamos = {
      useSteamOSConfig = true;
    };
  };
}
