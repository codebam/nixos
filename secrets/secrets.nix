let
  users = {
    yubikey-5c = "age1yubikey1q24yc9023p70svqhqhpftn5cqfd25f2wnpapazf470cs0cl0a9p6cq44w7m";
    yubikey-5c-nfc = "age1yubikey1qww4auye54gu430kzf37jww93aqt2gr4qx7d4xm2ukturxlr5uglgypnr2s";
  };
in
{
  "hashedpassword.age".publicKeys = [
    users.yubikey-5c
    users.yubikey-5c-nfc
  ];
  "github_token.age".publicKeys = [
    users.yubikey-5c
    users.yubikey-5c-nfc
  ];
}
