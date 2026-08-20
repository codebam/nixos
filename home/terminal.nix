{
  lib,
  config,
  ...
}:
{
  # One name for "the terminal", read by everything that has to spawn one:
  # sway's $term binding, the inode/directory handler in xdg.nix, and the
  # pinentry wrapper. Pointing those at a package each meant three places to
  # keep in agreement.
  options.defaultTerminal = lib.mkOption {
    type = lib.types.package;
    default = config.programs.rio.package;
    defaultText = lib.literalExpression "config.programs.rio.package";
    description = "Terminal emulator to launch wherever this config needs a new terminal window.";
  };
}
