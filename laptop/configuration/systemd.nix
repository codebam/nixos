_:

{
  systemd = {
    services = {
      systemd-remount-fs = {
        enable = false;
      };
    };
  };
}
