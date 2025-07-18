{ pkgs, lib, ... }:

{
  age = {
    # identityPaths = [
    #   ./secrets/identities/yubikey-5c.txt
    #   ./secrets/identities/yubikey-5c-nfc.txt
    # ];
    secrets = {
      duckdns-token.file = ../../secrets/duckdns-token.age;
      searx-secret.file = ../../secrets/searx-secret.age;
    };
    ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
    identityPaths = [
      "/persistent/etc/ssh/ssh_host_ed25519_key"
      "/persistent/etc/nixos/secrets/identities/yubikey-5c.txt"
      "/persistent/etc/nixos/secrets/identities/yubikey-5c-nfc.txt"
    ];
  };
}
