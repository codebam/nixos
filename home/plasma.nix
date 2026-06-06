_:

{
  programs.plasma = {
    enable = false;
    configFile.kdeglobals = {
      General = {
        TerminalApplication = "foot";
        TerminalService = "foot.desktop";
      };
    };
    configFile = {
      baloofilerc."Basic Settings".Indexing-Enabled = false;
      kcminputrc."Libinput/13364/832/Keychron Keychron V4 Mouse".PointerAccelerationProfile = 1;
      kcminputrc."Libinput/14096/21510/Pulsar 8K Dongle Gen.2".PointerAccelerationProfile = 1;
      kwinrc.EdgeBarrier.CornerBarrier = false;
      kwinrc.EdgeBarrier.EdgeBarrier = 0;
      kwinrc.Plugins.hidecursorEnabled = true;
    };
  };
}
