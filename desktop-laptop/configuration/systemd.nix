_:

{
  systemd.services = {
    # Both hosts get a freshly created root subvolume in stage 1, so remounting
    # / from fstab afterwards is unnecessary and races with that. Not shared
    # with the Steam Deck, which has never had it disabled.
    systemd-remount-fs.enable = false;
  };
}
