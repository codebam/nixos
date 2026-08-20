{
  pkgs,
  lib,
  ...
}:

let
  # Both harnesses read OPENROUTER_API_KEY from the environment. The key
  # already exists on this host inside the `hermes-env` sops secret, so it is
  # mounted a second time as `opencode-env` (same yaml key, owned by codebam)
  # rather than duplicated in secrets.yaml — one key, one place to rotate it.
  #
  # Only the names below are lifted out: hermes-env also carries chat-gateway
  # tokens that have no business in an interactive shell's environment.
  #
  # CLOUDFLARE_* are what opencode wants for the `cloudflare-workers-ai`
  # provider (account id goes into the endpoint path, the token into the auth
  # header). They live in the same hermes-env blob rather than a secret of
  # their own so that a missing value is a no-op instead of an activation
  # failure: add them with `sudo sops secrets/secrets.yaml`, as extra lines
  # inside the hermes-env value —
  #
  #   CLOUDFLARE_ACCOUNT_ID=<32-hex account id>
  #   CLOUDFLARE_API_KEY=<Workers AI API token>
  #
  # Until then the vars are simply unset and only the Cloudflare models are
  # unusable. Note the blob is also hermes' EnvironmentFile, so the agent
  # service sees these too.
  envNames = [
    "OPENROUTER_API_KEY"
    "CLOUDFLARE_ACCOUNT_ID"
    "CLOUDFLARE_API_KEY"
  ];
  loadKey = pkgs.writeShellScript "agent-load-env" ''
    secret=/run/secrets/opencode-env
    if [ -r "$secret" ]; then
      for name in ${lib.concatStringsSep " " envNames}; do
        value=$(${pkgs.gnused}/bin/sed -n "s/^$name=//p" "$secret" | tr -d '"' | head -n1)
        if [ -n "$value" ]; then export "$name=$value"; fi
      done
    fi
  '';

  # OpenRouter's Pareto Code Router picks a coder per request off the current
  # price/capability frontier, so there is no fixed per-token price to quote.
  # The floor below is what keeps it from bottoming out on a weak one.
  codingModel = "openrouter/pareto-code";

  # min_coding_score (0.0-1.0) is the router's capability floor: higher routes
  # to stronger and pricier coders, lower opens up cheap ones. 0.65 lands
  # mid-frontier and is the same floor the hermes module used. Omitting the
  # plugin entirely is NOT the neutral choice -- the router then picks the
  # strongest available coder, which is the expensive end.
  minCodingScore = 0.65;
  paretoPlugin = [
    {
      id = "pareto-router";
      min_coding_score = minCodingScore;
    }
  ];

  # Qwen 3.8 27B on Cloudflare Workers AI, offered as an alternate rather than
  # a default: it is cheap and long-context but a 27B model, so it is a
  # deliberate per-session pick, not the thing every task lands on.
  cfModel = "@cf/qwen/qwen3.8-27b";

  # Background turns (titles, summaries) do not need the router. $0.3/$1.2 per
  # Mtok, fixed.
  cheapModel = "minimax/minimax-m3";

  opencode = pkgs.symlinkJoin {
    name = "opencode-wrapped-${pkgs.opencode.version}";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode --run '. ${loadKey}'
    '';
  };

  # Pi ships its own updater and an install/version ping, neither of which
  # applies to a /nix/store copy it cannot write to.
  pi = pkgs.symlinkJoin {
    name = "pi-coding-agent-wrapped-${pkgs.pi-coding-agent.version}";
    paths = [ pkgs.pi-coding-agent ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/pi \
        --run '. ${loadKey}' \
        --set PI_SKIP_VERSION_CHECK 1 \
        --set PI_TELEMETRY 0
    '';
  };
  piSettings = {
    defaultProvider = "openrouter";
    defaultModel = codingModel;
    enableInstallTelemetry = false;
    # Adjust per session with the thinking-level picker when a task wants
    # more or less.
    defaultThinkingLevel = "medium";
    # Pi has no permission system, so this is the one guardrail it offers:
    # never load a project's own settings, resources, or extensions without an
    # explicit `/trust`.
    defaultProjectTrust = "never";
  };

  # pi 0.84.2 bundles an OpenRouter catalog that predates the Pareto router
  # (it knows openrouter/auto, auto-beta, free, and fusion), so the model is
  # added by hand. Custom models are upserted by id into the built-in
  # provider, which keeps its baseUrl and auth.
  #
  # samplingParams is merged verbatim into the request body, which is how the
  # router plugin gets through. Metadata mirrors openrouter/auto: the router
  # advertises a 2M window and variable pricing, so cost is left at zero
  # rather than guessed at.
  piModels = {
    providers.openrouter.models = [
      {
        id = codingModel;
        name = "Pareto Code Router";
        api = "openai-completions";
        reasoning = true;
        input = [ "text" ];
        contextWindow = 2000000;
        maxTokens = 32000;
        compat = {
          supportsDeveloperRole = false;
          thinkingFormat = "openrouter";
        };
        samplingParams.plugins = paretoPlugin;
      }
    ];
  };

  # Nix keys win over whatever pi last wrote, and a settings.json that pi (or a
  # half-finished edit) left unparseable is rebuilt rather than aborting
  # activation.
  piSettingsMerge = pkgs.writeShellScript "pi-settings-merge" ''
    set -eu
    settings="$HOME/.pi/agent/settings.json"
    mkdir -p "$(dirname "$settings")"
    current=$(${pkgs.jq}/bin/jq . "$settings" 2>/dev/null || echo '{}')
    printf '%s' "$current" \
      | ${pkgs.jq}/bin/jq --argjson managed ${lib.escapeShellArg (builtins.toJSON piSettings)} '. * $managed' \
      > "$settings.tmp"
    mv "$settings.tmp" "$settings"
  '';
in
{
  home = {
    packages = [
      opencode
      pi
    ];

    # Pi's settings.json is mutable state — `/settings` and the model picker
    # write to it — so it cannot be a read-only store symlink like opencode's
    # config. Merge instead, nix keys winning, the same way the hermes module
    # handled its own config.yaml.
    activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${piSettingsMerge}
    '';

    # models.json, unlike settings.json, is user-authored config that pi only
    # reads, so it can be a plain store symlink.
    file.".pi/agent/models.json".text = builtins.toJSON piModels;
  };

  # Written from nix rather than left to `opencode` itself: the TUI's model
  # picker persists into this same file, and a hand-picked model would
  # otherwise outlive the choice made here.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    # provider/model, so the openrouter provider plus the router's own
    # `openrouter/pareto-code` id doubles the prefix.
    model = "openrouter/${codingModel}";
    small_model = "openrouter/${cheapModel}";

    # opencode ships permissive: every tool runs unprompted. Kept that way on
    # purpose -- the prompts were more friction than guardrail here.
    permission = {
      edit = "allow";
      bash = "allow";
      external_directory = "allow";
      webfetch = "allow";
      task = "allow";
    };

    # The binary is a store path it cannot rewrite, and sessions should not
    # leave the machine unless asked for explicitly.
    autoupdate = false;
    share = "disabled";

    # Alternate, picked per session from the TUI's model list (`/models`);
    # the choice lives in opencode's own sqlite state, not in this file, so it
    # survives sessions without fighting the nix-managed config. Listing it
    # here is what puts `cloudflare-workers-ai` in that list -- the rest of the
    # model metadata (262k context, tool calls, vision, $0.45/$3.20 per Mtok)
    # comes from models.dev, and the endpoint is built from
    # CLOUDFLARE_ACCOUNT_ID with CLOUDFLARE_API_KEY as the token.
    provider.cloudflare-workers-ai.models.${cfModel} = { };

    # models.dev lists the router as non-reasoning, so opencode would send no
    # thinking parameters at all for it; `reasoning` here marks it capable and
    # `options.reasoning` sets the tier the underlying coder gets.
    #
    # Caveat: opencode has a standing report of provider model `options` being
    # dropped for OpenRouter rather than forwarded (anomalyco/opencode#27361,
    # closed unresolved). Whether 1.18.18 still drops them is unverified here,
    # and the failure is silent both ways -- no plugin means the router takes
    # the strongest, priciest coder, and no reasoning block means default
    # effort. Check one live request body before trusting either.
    provider.openrouter.models.${codingModel} = {
      reasoning = true;
      options = {
        plugins = paretoPlugin;
        reasoning.effort = "medium";
      };
    };
  };

}
