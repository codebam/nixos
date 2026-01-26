{ pkgs, ... }:
{
  services = {
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
    displayManager = {
      ly = {
        enable = true;
      };
    };
  };
}
