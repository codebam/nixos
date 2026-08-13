{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.gaming.extest = lib.mkEnableOption ''
    Steam's extest layer, which translates X11 input events for games that
    bypass SDL. Wanted on the Steam Deck, not on the desktop
  '';

  config = {
    programs = {
      steam = {
        enable = true;
        # Closed: an unused open port is not harmless here —
        # ip_unprivileged_port_start is 80 on the desktop, so any
        # unprivileged process can claim these and be internet-reachable.
        remotePlay.openFirewall = false;
        dedicatedServer.openFirewall = false;
        localNetworkGameTransfers.openFirewall = false;
        # One Proton, not two. proton-ge-bin used to be listed alongside this
        # and cost 1.5 GB for a build nothing was selected against — and
        # protontricks bakes whatever is here into its
        # STEAM_EXTRA_COMPAT_TOOLS_PATHS, so it was pinned twice over.
        extraCompatPackages = with pkgs; [
          proton-cachyos_x86_64_v3
        ];
        protontricks.enable = true;
        extest.enable = config.gaming.extest;
      };
      gamescope = {
        enable = true;
        package = pkgs.gamescope_git;
      };
      gamemode.enable = true;
    };
  };
}
