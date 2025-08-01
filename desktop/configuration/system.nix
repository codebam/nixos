_:

{
  system = {
    autoUpgrade = {
      enable = false;
      flake = "/etc/nixos";
      operation = "switch";
      dates = "daily";
      randomizedDelaySec = "10min";
      allowReboot = false;
    };
    stateVersion = "25.11";
  };
}
