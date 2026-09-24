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
      # Second OpenCode Go subscription, and the one Hermes leads with: the
      # hermes-env template below puts its placeholder in the unnumbered
      # OPENCODE_GO_API_KEY slot, which the credential pool's fill_first
      # order tries before the numbered sibling, so the first subscription
      # becomes the fallback entry. No wrapper exports it, so no other
      # agent picks it up.
      opencode-go-api-key-2 = {
        owner = "codebam";
        group = "users";
      };
      # CrofAI API key for the CrofAI provider in opencode, pi, and dsh;
      # home/agents.nix exports it as CROFAI_API_KEY from the wrappers.
      crofai-api-key = {
        owner = "codebam";
        group = "users";
      };
      # Telegram bot token consumed only by the Hermes gateway. It is not in
      # home/agents.nix's secretVars: no interactive agent wrapper needs it.
      hermes-bot-telegram-key = {
        owner = "codebam";
        group = "users";
      };
      # Tavily API key backing Hermes' web.extract_backend (home/hermes.nix).
      # No wrapper exports it; only the hermes-env template below consumes it.
      tavily-api-key = {
        owner = "codebam";
        group = "users";
      };
      searx-secret = { };
    };

    # Rebuild hermes-env as a runtime file for the Hermes agent. The base keys
    # come from the same individual sops keys the wrappers read; the plan keys
    # are added under the names Hermes resolves them by, so its built-in
    # OpenCode Go and DeepSeek providers authenticate, its hand-declared
    # Qwen Token Plan / CrofAI providers find their key_env, the gateway gets
    # the Telegram bot token, and its pinned web.extract_backend (home/hermes.nix)
    # finds the Tavily key. Both OpenCode Go subscriptions enter the
    # credential pool as the unnumbered/numbered pair (the numbered sibling
    # is auto-discovered), and fill_first tries the unnumbered slot first --
    # so the placeholders are crossed below: the second subscription leads
    # and the first one backs it up when a spent subscription rotates
    # mid-session.
    # owner codebam so Home Manager activation can read it and copy it into
    # $HERMES_HOME/.env.
    templates."hermes-env" = {
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter-api-key}
        CONTEXT7_API_KEY=${config.sops.placeholder.context7-api-key}
        CLOUDFLARE_API_KEY=${config.sops.placeholder.cloudflare-api-key}
        CLOUDFLARE_ACCOUNT_ID=${config.sops.placeholder.cloudflare-account-id}
        QWEN_TOKEN_PLAN_API_KEY=${config.sops.placeholder.qwen-api-key}
        DEEPSEEK_API_KEY=${config.sops.placeholder.deepseek-api-key}
        OPENCODE_GO_API_KEY=${config.sops.placeholder.opencode-go-api-key-2}
        OPENCODE_GO_API_KEY_2=${config.sops.placeholder.opencode-go-api-key}
        CROFAI_API_KEY=${config.sops.placeholder.crofai-api-key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily-api-key}
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.hermes-bot-telegram-key}
      '';
      owner = "codebam";
      group = "users";
      mode = "0400";
    };
  };
}
