_:

{
  # The dashboard watches the checkouts on this host's persistent disk, so it
  # is desktop-only: laptop and steamdeck have no ~/Documents/git of the same
  # shape. nginx fronts it at /codedash (desktop/configuration/services.nix).
  services.codedash = {
    enable = true;
    user = "codebam";
    root = "/home/codebam/Documents/git";
    port = 8090;
    allowActions = true;
  };
}
