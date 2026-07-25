_: {
  # The desktop pins cpuFreqGovernor = "performance"; the laptop deliberately
  # does not. power-profiles-daemon is used rather than TLP because the two
  # conflict, and ppd needs no per-machine tuning.
  services = {
    power-profiles-daemon.enable = true;
    upower.enable = true;
    thermald.enable = true;
  };

  powerManagement = {
    enable = true;
    powertop.enable = true;
  };
}
