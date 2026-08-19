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
  # Only OPENROUTER_API_KEY is lifted out: hermes-env also carries chat-gateway
  # tokens that have no business in an interactive shell's environment.
  loadKey = pkgs.writeShellScript "openrouter-load-key" ''
    secret=/run/secrets/opencode-env
    if [ -r "$secret" ]; then
      key=$(${pkgs.gnused}/bin/sed -n 's/^OPENROUTER_API_KEY=//p' "$secret" | tr -d '"' | head -n1)
      [ -n "$key" ] && export OPENROUTER_API_KEY="$key"
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
    # Cheapest reasoning tier that still routes; raise per session with the
    # thinking-level picker when a task actually needs it.
    defaultThinkingLevel = "low";
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

    # opencode ships permissive: every tool runs unprompted. Edits and shell
    # commands ask first here, since these harnesses run against this flake.
    permission = {
      edit = "ask";
      bash = "ask";
      external_directory = "ask";
      webfetch = "ask";
      task = "ask";
    };

    # The binary is a store path it cannot rewrite, and sessions should not
    # leave the machine unless asked for explicitly.
    autoupdate = false;
    share = "disabled";

    provider.openrouter.models.${codingModel}.options.plugins = paretoPlugin;
  };

}
