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
      qwen-api-key = {
        owner = "codebam";
        group = "users";
      };
      deepseek-api-key = {
        owner = "codebam";
        group = "users";
      };
      # OpenCode Go subscription key, exported as OPENCODE_API_KEY by the
      # wrapper in home/agents.nix. Its own secret rather than one more line in
      # hermes-env: that blob is the shared agent env file, and a personal
      # subscription key has no business in a server process's environment.
      opencode-go-api-key = {
        owner = "codebam";
        group = "users";
      };
      searx-secret = { };
    };
  };
}
