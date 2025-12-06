_:

{
  programs.plasma = {
    enable = true;
    configFile.kdeglobals = {
      General = {
        TerminalApplication = "foot";
        TerminalService = "foot.desktop";
      };
    };
    configFile = {
      kcminputrc."Libinput/13364/832/Keychron Keychron V4 Mouse".PointerAccelerationProfile = 1;
      kwinrc.EdgeBarrier.CornerBarrier = false;
      kwinrc.EdgeBarrier.EdgeBarrier = 0;
      kwinrc.Plugins.hidecursorEnabled = true;
    };
  };
}
