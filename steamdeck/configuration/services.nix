{lib, ...}:

{
  services = {
    desktopManager.plasma6.enable = lib.mkForce true;
  };
}
