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
        mode = "0400";
      };
      context7-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      cloudflare-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      cloudflare-account-id = {
        owner = "codebam";
        mode = "0400";
      };
      qwen-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      deepseek-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # OpenCode Go subscription key, exported as OPENCODE_API_KEY by the
      # wrapper in home/agents.nix. Kept as its own secret: it is a personal
      # subscription key, not part of the shared agent environment.
      opencode-go-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Second OpenCode Go subscription, and the one Hermes leads with: the
      # hermes-env template below puts its placeholder in the unnumbered
      # OPENCODE_GO_API_KEY slot, which the credential pool's fill_first
      # order tries before the numbered sibling, so the first subscription
      # becomes the fallback entry. The dsh launchers export it too, as
      # OPENCODE_API_KEY_2 (loadDshKey in home/agents.nix), so both
      # subscriptions resolve inside dsh and `dsh-subscription` flips which
      # one OPENCODE_API_KEY names; no other agent picks it up.
      opencode-go-api-key-2 = {
        owner = "codebam";
        mode = "0400";
      };
      # NanoGPT API key for the `nano-gpt` provider in opencode (as
      # NANO_GPT_API_KEY, the name models.dev lists for it) and in pi, dsh,
      # and Hermes (as NANOGPT_API_KEY, the name NanoGPT's own docs use);
      # home/agents.nix exports both names from the wrappers, and the
      # hermes-env template below feeds Hermes.
      nanogpt-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Telegram bot token consumed only by the Hermes gateway. It is not in
      # home/agents.nix's secretVars: no interactive agent wrapper needs it.
      hermes-bot-telegram-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Telegram echoes this on every webhook delivery; the gateway refuses
      # to start in webhook mode without it (GHSA-3vpc-7q5r-276h). Same
      # audience as the bot token: the hermes-env template only.
      telegram-webhook-secret = {
        owner = "codebam";
        mode = "0400";
      };
      # cloudflared credentials for the hermes-telegram tunnel
      # (desktop/configuration/cloudflared.nix), loaded by the tunnel unit as
      # a runtime credential -- systemd reads it as root, so root ownership
      # is fine.
      cloudflared-tunnel-credentials = { };
      # Tavily API key backing Hermes' web.extract_backend (home/hermes.nix).
      # No wrapper exports it; only the hermes-env template below consumes it.
      tavily-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Bearer for the agentic-inbox email MCP bridge (home/email-mcp.nix):
      # the bridge launcher exports it as MCP_AUTH_TOKEN so the stdio bridge
      # authenticates to the deployed Worker without depending on the
      # interactive `wrangler login` state. It is a Settings-minted `ain1_`
      # scoped access token for the codebam@codebam.ca mailbox; /mcp verifies
      # it like the scoped surface (agentic-inbox d7e44ef) and binds the
      # session to that mailbox and its read/draft/send scopes.
      email-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Desktop-app OAuth client JSON for the Google Calendar MCP server
      # (home/google-calendar-mcp.nix). The launcher exports it as
      # GOOGLE_OAUTH_CREDENTIALS. Google treats installed-app client secrets
      # as non-confidential, but it stays out of the store with the rest.
      google-calendar-oauth = {
        owner = "codebam";
        mode = "0400";
      };
      # Root and codebam password hashes live here so they are not
      # committed as plaintext. Same hashes as before (no rotation, per
      # owner request); wired via hashedPasswordFile in users.nix below.
      # The secrets themselves are verifier hashes, but keeping them in
      # SOPS avoids leaving them in git history for current generations.
      root-hashed-password = {
        mode = "0400";
      };
      codebam-hashed-password = {
        mode = "0400";
      };
      searx-secret = { };
    };

    # Rebuild hermes-env as a runtime file for the Hermes agent. The base keys
    # come from the same individual sops keys the wrappers read; the plan keys
    # are added under the names Hermes resolves them by, so its built-in
    # OpenCode Go and DeepSeek providers authenticate, its hand-declared
    # Qwen Token Plan and NanoGPT providers find their key_envs, the gateway
    # gets the Telegram bot token and its webhook secret, and its pinned
    # web.extract_backend (home/hermes.nix) finds the Tavily key. Both
    # OpenCode Go subscriptions enter the
    # credential pool as the unnumbered/numbered pair (the numbered sibling
    # is auto-discovered), and fill_first tries the unnumbered slot first --
    # so the placeholders are crossed below: the second subscription leads
    # and the first one backs it up when a spent subscription rotates
    # mid-session.
    # owner codebam so Home Manager activation can read it and copy it into
    # $HERMES_HOME/.env. CLOUDFLARE_API_TOKEN carries the same sops value as
    # CLOUDFLARE_API_KEY, under the name the cf CLI (pkgs/cf.nix) resolves.
    templates."hermes-env" = {
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter-api-key}
        CONTEXT7_API_KEY=${config.sops.placeholder.context7-api-key}
        CLOUDFLARE_API_KEY=${config.sops.placeholder.cloudflare-api-key}
        CLOUDFLARE_ACCOUNT_ID=${config.sops.placeholder.cloudflare-account-id}
        CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-api-key}
        QWEN_TOKEN_PLAN_API_KEY=${config.sops.placeholder.qwen-api-key}
        DEEPSEEK_API_KEY=${config.sops.placeholder.deepseek-api-key}
        OPENCODE_GO_API_KEY=${config.sops.placeholder.opencode-go-api-key-2}
        OPENCODE_GO_API_KEY_2=${config.sops.placeholder.opencode-go-api-key}
        NANOGPT_API_KEY=${config.sops.placeholder.nanogpt-api-key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily-api-key}
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.hermes-bot-telegram-key}
        TELEGRAM_WEBHOOK_SECRET=${config.sops.placeholder.telegram-webhook-secret}
      '';
      owner = "codebam";
      group = "users";
      mode = "0400";
    };
  };
}
