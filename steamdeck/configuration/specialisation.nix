_: {
  # Boot entry that keeps the current root instead of archiving it -- useful
  # when something in /etc or /var needs to survive one more boot.
  specialisation.noCleanup.configuration.cleanupRoot.mode = "keep";
}
