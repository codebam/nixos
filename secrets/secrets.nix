let
  users = {
    yubikey-5c = "age1yubikey1q24yc9023p70svqhqhpftn5cqfd25f2wnpapazf470cs0cl0a9p6cq44w7m";
    yubikey-5c-nfc = "age1yubikey1qww4auye54gu430kzf37jww93aqt2gr4qx7d4xm2ukturxlr5uglgypnr2s";
    desktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXDw2gbAdpXNw9qNgE73f6UHT09fk5pFAxepu7RaVFd root@nixos-desktop";
  };
in
{
  "duckdns-token.age".publicKeys = [
    users.desktop
    users.yubikey-5c
    users.yubikey-5c-nfc
  ];
  "searx-secret.age".publicKeys = [
    users.desktop
    users.yubikey-5c
    users.yubikey-5c-nfc
  ];
}
