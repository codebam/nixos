_:

{
  system = {
    stateVersion = "26.05";
  };
  systemd.user.services.steamos-manager.after = [ "cecd.service" ];
}
