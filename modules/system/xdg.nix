{ pkgs, ... }:
{
  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "*";
      xdgOpenUsePortal = true;
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };
  };
}
