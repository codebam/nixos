{ pkgs, ... }:
{
  services = {
    mullvad-vpn = {
      enable = false;
      package = pkgs.mullvad-vpn;
    };
    ivpn = {
      enable = true;
    };
    displayManager = {
      ly = {
        enable = false;
      };
    };
  };
}
