{
  config,
  ...
}:

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
      # One sops key per credential, each mounted as its own file. The agent
      # wrappers (home/agents.nix) read these directly, and the template below
      # reassembles the old hermes-env file for Hermes itself.
      openrouter-api-key = {
        owner = "codebam";
        group = "users";
      };
      context7-api-key = {
        owner = "codebam";
        group = "users";
      };
      cloudflare-api-key = {
        owner = "codebam";
        group = "users";
      };
      cloudflare-account-id = {
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
      # wrapper in home/agents.nix. Kept as its own secret: it is a personal
      # subscription key, not part of the shared agent environment.
      opencode-go-api-key = {
        owner = "codebam";
        group = "users";
      };
      # CrofAI API key for the CrofAI provider in opencode, pi, and dsh;
      # home/agents.nix exports it as CROFAI_API_KEY from the wrappers.
      crofai-api-key = {
        owner = "codebam";
        group = "users";
      };
      searx-secret = { };
    };

    # Rebuild the old hermes-env as a runtime file from the individual keys.
    # owner codebam so Home Manager activation can read it and copy it into
    # $HERMES_HOME/.env.
    templates."hermes-env" = {
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter-api-key}
        CONTEXT7_API_KEY=${config.sops.placeholder.context7-api-key}
        CLOUDFLARE_API_KEY=${config.sops.placeholder.cloudflare-api-key}
        CLOUDFLARE_ACCOUNT_ID=${config.sops.placeholder.cloudflare-account-id}
      '';
      owner = "codebam";
      group = "users";
      mode = "0400";
    };
  };
}
