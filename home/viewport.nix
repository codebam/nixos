{ pkgs, lib, ... }:

{
  # Viewport's bootstrap config: the tier that has to keep working when the web
  # shell does not. The shell is fetched at startup, and if it fails to load
  # anything it owned dies with it — a binding defined here still works in that
  # state, which is the difference between a broken desktop and a machine you
  # cannot quit without switching to a TTY.
  #
  # No "binds" block on purpose. Defining one at all suppresses the built-in
  # defaults, and the scrolling layout picks a different set of movement keys
  # than tiling does; naming any would mean taking on the whole keymap.
  xdg.configFile."viewport/config.json".text = builtins.toJSON {
    layout = "scrolling";

    # Variable refresh rate. Tested against each monitor at startup and left
    # off for any that refuses it, so this is safe to ask for unconditionally.
    adaptive_sync = true;

    # Seconds. The compositor runs the locker rather than drawing the lock
    # screen itself, so swaylock can crash without unlocking anything.
    idle = {
      lock_after = 600;
      lock_command = "${lib.getExe pkgs.swaylock} -f";
      blank_after = 900;
    };
  };
}
