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
      # One sops key per credential, each mounted as its own file. The agent
      # wrappers (home/agents.nix) read these directly; nothing else
      # reassembles them into a shared environment file.
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
      # Gemini Platform (formerly Vertex AI) API key, used instead of ADC.
      # home/agents.nix's secretVars exports it under both names the harnesses
      # resolve: GOOGLE_CLOUD_API_KEY for pi-ai (dsh, pi) and
      # GOOGLE_VERTEX_API_KEY for opencode.
      gemini-platform-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # The Gemini Platform project the key belongs to. The key's express
      # endpoint resolves to its own region (us-central1 here), which does not
      # serve the Gemini 4 models, so both harnesses address the
      # project-scoped global endpoint instead. Read at runtime: opencode's
      # loader exports it as GOOGLE_VERTEX_PROJECT, and the dsh settings merge
      # builds the route's baseURL from it -- keeping it out of the store.
      gemini-platform-project = {
        owner = "codebam";
        mode = "0400";
      };
      # Google AI Studio (the Gemini API at generativelanguage.googleapis.com)
      # API key. It is a separate credential from the Gemini Platform key
      # above: AI Studio keys do not authenticate against aiplatform, and
      # Platform keys do not authenticate against generativelanguage.
      # home/agents.nix exports it as GEMINI_API_KEY (pi-ai's `google`
      # provider) and GOOGLE_GENERATIVE_AI_API_KEY (the AI SDK name opencode's
      # `google` provider also resolves).
      google-aistudio-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # The Google Cloud project the AI Studio key is billed to. Neither
      # harness sends it -- the Gemini API endpoint is not project-scoped --
      # but it is mounted alongside the key so the pair stays together.
      google-aistudio-project = {
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
      # Second OpenCode Go subscription. The dsh launchers export it as
      # OPENCODE_API_KEY_2 (loadDshKey in home/agents.nix), so both
      # subscriptions resolve inside dsh and `dsh-subscription` flips which
      # one OPENCODE_API_KEY names; no other agent picks it up.
      opencode-go-api-key-2 = {
        owner = "codebam";
        mode = "0400";
      };
      # NanoGPT API key for the `nano-gpt` provider in opencode (as
      # NANO_GPT_API_KEY, the name models.dev lists for it) and in pi and dsh
      # (as NANOGPT_API_KEY, the name NanoGPT's own docs use); home/agents.nix
      # exports both names from the wrappers.
      nanogpt-api-key = {
        owner = "codebam";
        mode = "0400";
      };
      # Appservice tokens for the local Matrix webhook bridge. hs_token is
      # presented by the homeserver when pushing transactions; as_token would
      # let the bridge act as its namespace user if needed.
      matrix-bridge-hs-token = {
        sopsFile = ../../secrets/matrix-bridge-hs-token.yaml;
        owner = "codebam";
        mode = "0400";
      };
      matrix-bridge-as-token = {
        sopsFile = ../../secrets/matrix-bridge-as-token.yaml;
        owner = "codebam";
        mode = "0400";
      };
      # Access token for @dshbot:codebam.ca, now used by the appservice webhook
      # bridge to post replies back into Matrix rooms. Kept in its own
      # encrypted file so the token can be rotated without touching the
      # shared secrets.yaml.
      dsh-im-matrix-token = {
        sopsFile = ../../secrets/dsh-im-matrix.yaml;
        owner = "codebam";
        mode = "0400";
      };
      # Telegram bot token for dsh-im's Telegram bot (home/agents.nix's
      # loadDshImKeys exports it under the bot's credential ref). Deliberately
      # not in home/agents.nix's shared secretVars: only that loader reads it,
      # so no other harness sees the token.
      qwen-bot-telegram-key = {
        owner = "codebam";
        mode = "0400";
      };
      # cloudflared credentials for the tg.codebam.ca tunnel
      # (desktop/configuration/cloudflared.nix), loaded by the tunnel unit as
      # a runtime credential -- systemd reads it as root, so root ownership is
      # fine. The tunnel now fronts the Matrix appservice webhook bridge.
      cloudflared-tunnel-credentials = { };
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
      #
      # neededForUsers is mandatory: userborn reads hashedPasswordFile
      # while it builds /etc/shadow, and that happens before the regular
      # sops-install-secrets.service (which is ordered After=userborn).
      # Without this flag the file does not exist yet, userborn logs
      # "Failed to read hashedPasswordFile" and leaves the account locked.
      # neededForUsers installs these into /run/secrets-for-users from
      # sops-install-secrets-for-users.service, ordered before user
      # creation; its path is still config.sops.secrets.<name>.path.
      # They must stay root-owned, which is why no owner/group is set.
      root-hashed-password = {
        neededForUsers = true;
        mode = "0400";
      };
      codebam-hashed-password = {
        neededForUsers = true;
        mode = "0400";
      };
      searx-secret = { };
    };
  };
}
