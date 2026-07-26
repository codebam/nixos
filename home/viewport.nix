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

    # Modes are left to the display by default, and this panel nominates a
    # timing that is not its fastest. max_refresh takes the highest refresh
    # rate available at the preferred resolution — only the refresh rate, so
    # the resolution cannot quietly drop in exchange.
    outputs = {
      "*" = {
        max_refresh = true;
      };
    };

    # Variable refresh rate. Tested against each monitor at startup and left
    # off for any that refuses it, so this is safe to ask for unconditionally.
    adaptive_sync = true;

    # OLED. Everything below is about one property of the panel: a pixel that
    # shows the same thing for hours ages faster than its neighbours.
    #
    # The bar is the worst offender by a distance — same height, same position,
    # same clock in the same corner, every waking hour. "auto" hides it and
    # reveals it while Mod4 is held, which is already held for every binding
    # that would make you want to look at it. Mod4+n still pins it when
    # something needs watching.
    bar = "auto";

    # True black, not a dark grey: an OLED pixel showing #000000 is off, and
    # draws no current at all. The two washes of colour in the default
    # background are the other steady light source, so they go too — on this
    # panel they are a gradient that never moves rather than depth.
    theme = {
      bg = "#000000";
      glow-1 = "transparent";
      glow-2 = "transparent";
      bar-bg = "#000000";
      bar-border = "#1a1a1a";
    };

    # Seconds. The compositor runs the locker rather than drawing the lock
    # screen itself, so swaylock can crash without unlocking anything.
    idle = {
      lock_after = 600;
      lock_command = "${lib.getExe pkgs.swaylock} -f";
      blank_after = 900;
    };
  };
}
