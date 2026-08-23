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
      # The yaml key is named hermes-env for history's sake: it started life
      # as the env file of the hermes agent service, and opencode and pi took
      # over as the harnesses on this machine without a key rotation.
      # Mounted separately for codebam so the opencode and pi wrappers can
      # lift OPENROUTER_API_KEY out of it.
      opencode-env = {
        key = "hermes-env";
        owner = "codebam";
        group = "users";
      };
      # Same key again, this time left root-owned: litellm runs
      # under a DynamicUser, and systemd reads EnvironmentFile as root before
      # the unit drops privileges, so no chown is needed and none is wanted.
      litellm-env = {
        key = "hermes-env";
      };
      searx-secret = { };
      # Read by the cliamp wrapper in home/cliamp.nix, which runs as codebam.
      navidrome-password = {
        owner = "codebam";
        group = "users";
      };
      "unredacted.org" = {
        sopsFile = ../../secrets/passwords.enc.yaml;
        owner = "codebam";
        group = "users";
      };
    };
  };
}
