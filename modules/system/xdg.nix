{ pkgs, ... }:
{
  xdg = {
    autostart.enable = true;
    portal = {
      config.common.default = "*";
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };
  };
}
