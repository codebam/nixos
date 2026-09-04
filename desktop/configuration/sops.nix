{ config, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";

    # termsonic reads its server URL, username and password out of one TOML
    # file, with no environment-variable path, so the whole file is rendered
    # from the secret rather than mounted alongside it. The wrapper in
    # home/termsonic.nix points `-config` at the result.
    templates."termsonic.toml" = {
      content = ''
        BaseURL = "http://localhost:4533/navidrome"
        Username = "codebam"
        Password = "${config.sops.placeholder.navidrome-password}"
      '';
      owner = "codebam";
      group = "users";
    };

    # The [subidy] section of mopidy's config, read by the user service in
    # home/mopidy.nix. mopidy has no way to pull one value out of a file, so
    # the section is rendered whole.
    templates."mopidy-subidy.conf" = {
      content = ''
        [subidy]
        url = http://localhost:4533/navidrome
        username = codebam
        password = ${config.sops.placeholder.navidrome-password}
      '';
      owner = "codebam";
      group = "users";
    };

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
      qwen-api-key = {
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
