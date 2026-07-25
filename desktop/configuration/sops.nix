_:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age = {
      sshKeyPaths = [ "/persistent/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/persistent/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    secrets = {
      navidrome-lastfm = {
        owner = "navidrome";
        group = "navidrome";
      };
      mopidy-subidy = {
        owner = "codebam";
        group = "users";
      };
      duckdns-token = {
        owner = "codebam";
        group = "users";
      };
      searx-secret = { };
      "unredacted.org" = {
        sopsFile = ../../secrets/passwords.enc.yaml;
        owner = "codebam";
        group = "users";
      };
    };
  };
}
