_:

{
  jovian = {
    decky-loader = {
      enable = true;
      user = "codebam";
      stateDir = "/home/codebam/.config/decky-loader";
    };
    steam = {
      enable = true;
      user = "codebam";
      autoStart = true;
      # "Switch to Desktop" launches this session: jovian's setup unit runs
      # `steamosctl set-default-desktop-session ${desktopSession}.desktop`,
      # and the value is validated against the session names this system
      # provides. viewport.desktop comes from steamdeck/configuration/
      # viewport.nix; sway stays installed so SDDM can still pick it by hand.
      desktopSession = "viewport";
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
