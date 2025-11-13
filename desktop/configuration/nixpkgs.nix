_:

{
  nixpkgs = {
    overlays = [ (final: prev: { }) ];
    config.rocmSupport = false;
  };
}
