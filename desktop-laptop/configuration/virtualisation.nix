_: {
  # Rootless podman containers are placed in a user slice by the OpenSandbox
  # memory/CPU budget, whose IOWeight needs the io controller. Upstream's
  # user@.service only delegates pids, memory and cpu to the user manager.
  systemd.services."user@".serviceConfig.Delegate = "pids memory cpu io";

  virtualisation = {
    containers = {
      enable = true;
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
