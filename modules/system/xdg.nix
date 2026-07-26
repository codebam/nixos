{ pkgs, ... }:
{
  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "*";

      # Viewport names itself in XDG_CURRENT_DESKTOP, so the portal looks for a
      # viewport-portals.conf and finds none — the package ships one, but a
      # package's /etc is not this system's /etc. Without it the frontend
      # exposes no org.freedesktop.portal.ScreenCast whatsoever: Firefox's
      # getDisplayMedia rejects with no sources and OBS offers no screen
      # capture, neither of them mentioning a portal.
      #
      # wlr.enable below writes exactly this mapping for sway, which is what
      # the sway-portals.conf on this system is.
      config.viewport = {
        default = [ "gtk" "*" ];
        "org.freedesktop.impl.portal.Settings" = [ "viewport" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };

      xdgOpenUsePortal = true;
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };
  };
}
