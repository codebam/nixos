_:

{
  # Offload builds to the on-demand GCE spot instance. The instance stops itself
  # after 10 idle minutes, so leaving this on costs nothing between rebuilds.
  services.gcpNixBuilder.enable = true;
}
