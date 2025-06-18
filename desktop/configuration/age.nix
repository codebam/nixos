{ pkgs, lib, ... }:

{
  age = {
    # identityPaths = [
    #   ./secrets/identities/yubikey-5c.txt
    #   ./secrets/identities/yubikey-5c-nfc.txt
    # ];
    secrets.duckdns-token.file = ../../secrets/duckdns-token.age;
    ageBin = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
    identityPaths = [
      "/persistent/etc/ssh/ssh_host_ed25519_key"
    ];
  };
}
