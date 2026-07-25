{ pkgs, ... }:
{
  services.smartd = {
    enable = true;
    autodetect = true;
    # smartd's default notification path is mail, which isn't configured here.
    # Route failures to the desktop notification daemon instead.
    notifications.wall.enable = true;
  };

  environment.systemPackages = [ pkgs.smartmontools ];
}
