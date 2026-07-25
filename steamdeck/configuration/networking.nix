_:

{
  # systemd-networkd-wait-online is already disabled for every host in
  # modules/system/networking.nix.
  networking = {
    hostName = "nixos-steamdeck";
  };
}
