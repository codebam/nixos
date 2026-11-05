{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Launching the session from a VT, with no display manager in front of it.
  #
  # pam_systemd gives a VT login XDG_RUNTIME_DIR and starts the user manager,
  # but it does not export DBUS_SESSION_BUS_ADDRESS. startplasma-wayland
  # hard-requires a session bus, and the fallback upstream ships
  # (plasma-dbus-run-session-if-needed) starts a private dbus-daemon. On a
  # systemd host that private bus has no org.freedesktop.systemd1, so
  # startplasma quietly falls back to its classic boot path instead of the
  # systemd one. Point it at the user manager's own bus, whose socket
  # dbus.socket already provides.
  startplasma-tty = pkgs.writeShellApplication {
    name = "startplasma-tty";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        # Socket activation normally has this up by the time a login shell
        # runs; start it explicitly so a fast login cannot race it.
        ${config.systemd.package}/bin/systemctl --user start dbus.socket || true
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      fi
      if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
        echo "startplasma-tty: no user D-Bus socket at $XDG_RUNTIME_DIR/bus" >&2
        echo "startplasma-tty: is the systemd user manager running for this login?" >&2
        exit 1
      fi
      exec ${lib.getExe' pkgs.kdePackages.plasma-workspace "startplasma-wayland"} "$@"
    '';
  };
in
{
  # Wayland session only. No display manager is enabled: nothing starts a
  # session by itself, and the VT stays at a text login until
  # `startplasma-tty` is run.
  services = {
    desktopManager.plasma6.enable = true;

    # plasma6.nix sets these with mkDefault. Both are deliberate here: the
    # screen reader is off fleet-wide for closure reasons
    # (modules/services/default.nix), and the desktop pins the CPU governor to
    # performance in desktop/configuration/systemd.nix -- PPD is a laptop
    # concern here (README) and would put its platform-profile handling on top
    # of that. Powerdevil still does brightness and suspend without it.
    orca.enable = false;
    power-profiles-daemon.enable = false;
  };

  environment.systemPackages = [ startplasma-tty ];

  # Plasma's module turns the KDE PIM suite on by default. That pulls akonadi,
  # KMail and Kontact, and autostarts the akonadi server in the session. A
  # Plasma desktop does not need it; add individual apps instead if wanted.
  programs.kde-pim.enable = false;
}
