{ pkgs, inputs, ... }:

let
  # The flake's recommended backend, named the way the desktop names it
  # (desktop/configuration/environment.nix) so the session's Exec below, the
  # portal's declaration and the closure all agree on one build.
  viewport = inputs.viewport.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Screen sharing is routed with the compositor: Viewport answers ScreenCast
  # itself and the wlroots portal is the fallback. Without this, screen
  # sharing fails with nothing in any log naming a portal.
  imports = [ inputs.viewport.nixosModules.portal ];
  programs.viewport.portals.enable = true;
  programs.viewport.package = viewport;

  environment.systemPackages = [ viewport ];

  # SDDM's session entry, and the name "Switch to Desktop" starts:
  # `providedSessions` is what jovian.steam.desktopSession validates against.
  #
  # No `--config`, deliberately: the session reads the user's
  # ~/.config/viewport/config.json (home/viewport.nix) the way the desktop
  # starts it. The flake's session module would pass a config of its own, and
  # the bootstrap keymap defined here would be someone else's.
  services.displayManager.sessionPackages = [
    (pkgs.writeTextFile {
      name = "viewport-session";
      destination = "/share/wayland-sessions/viewport.desktop";
      text = ''
        [Desktop Entry]
        Name=Viewport
        Comment=Wayland compositor
        Exec=${viewport}/bin/viewport
        Type=Application
      '';
      passthru.providedSessions = [ "viewport" ];
    })
  ];

  # What makes the user manager's session graphical: the compositor starts
  # this target, and the binding carries graphical-session.target with it.
  # xdg-desktop-portal carries Requisite=graphical-session.target as of 1.22
  # and fails its job while that is inactive -- no Settings interface, and
  # every application on a light theme with nothing in the log to say why.
  systemd.user.targets.viewport-session = {
    description = "Viewport compositor session";
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };
}
