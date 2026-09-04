{
  pkgs,
  lib,
  osConfig ? { },
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

    qwen_secret=/run/secrets/qwen-api-key
    if [ -r "$qwen_secret" ]; then
      QWEN_API_KEY=$(cat "$qwen_secret")
      export QWEN_API_KEY
      # pi resolves its built-in qwen-token-plan* providers from this exact
      # name (env-api-keys.ts envMap); same plan key, second name.
      QWEN_TOKEN_PLAN_API_KEY=$QWEN_API_KEY
      export QWEN_TOKEN_PLAN_API_KEY
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

  # The litellm gateway from desktop/configuration/litellm.nix: qwen3.8 27B on
  # the local card, transparently continued on OpenRouter's copy of the same
  # model once a session outgrows the 160k the GPU can hold. One model id from
  # opencode's side; the switch happens inside the proxy.
  gatewayUrl = "http://127.0.0.1:4000/v1";
  gatewayModel = "qwen3.8";

  # Qwen Cloud Token Plan, following the vendor's opencode recipe
  # (docs.qwencloud.com/developer-guides/clients-and-developer-tools/opencode):
  # the Anthropic Messages endpoint rather than the OpenAI-compatible one.
  # The provider id stays `qwen` so existing `qwen/<model>` selections and
  # session history resolve unchanged.
  #
  # The model set is exactly what the plan key serves (GET /models on the
  # compatible-mode endpoint): the eight chat models of the Personal Edition.
  # The key also lists wan2.7-image{,-pro} and qwen-audio-3.0-*, but those
  # answer neither chat-completions nor messages requests (image-generation,
  # TTS, and realtime APIs respectively), so they have no place in either
  # harness. Limits are the documented 983616-token window and per-model
  # output caps; thinking is pinned the way the recipe pins it (effort for
  # the 3.8 pair, a fixed 8192-token budget for 3.7/3.6/glm, default-on for
  # the deepseek pair).
  qwenProvider = {
    qwen = {
      npm = "@ai-sdk/anthropic";
      name = "Qwen Cloud (Token Plan)";
      options = {
        baseURL = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic/v1";
        apiKey = "{env:QWEN_API_KEY}";
      };
      models = {
        "qwen3.8-max" = {
          name = "Qwen3.8 Max";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 131072;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
          options.effort = "xhigh";
        };
        "qwen3.8-flash" = {
          name = "Qwen3.8 Flash";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 131072;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
          options.effort = "xhigh";
        };
        "qwen3.7-max" = {
          name = "Qwen3.7 Max";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 131072;
          };
          options.thinking = {
            type = "enabled";
            budgetTokens = 8192;
          };
        };
        "qwen3.7-plus" = {
          name = "Qwen3.7 Plus";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
          options.thinking = {
            type = "enabled";
            budgetTokens = 8192;
          };
        };
        "qwen3.6-flash" = {
          name = "Qwen3.6 Flash";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 65536;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
          options.thinking = {
            type = "enabled";
            budgetTokens = 8192;
          };
        };
        "glm-5.2" = {
          name = "GLM-5.2";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 131072;
          };
          options.thinking = {
            type = "enabled";
            budgetTokens = 8192;
          };
        };
        "deepseek-v4-pro" = {
          name = "DeepSeek V4 Pro";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 384000;
          };
        };
        "deepseek-v4-flash-0731" = {
          name = "DeepSeek V4 Flash 0731";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 384000;
          };
        };
      };
    };
  };

  # Only the desktop has the card and therefore the gateway; this same home
  # config lands on the laptop and the steamdeck, where pointing the default
  # model at a port nothing is listening on would break every session. Those
  # hosts stay on the router.
  hasGateway = osConfig.services.litellm.enable or false;

  # Auto-compaction fires at `limit.input - compaction.reserved` -- opencode
  # 1.18.18 only honours `compaction.reserved` when the model declares
  # `limit.input`, and falls back to `limit.context - maxOutputTokens` when it
  # does not. 160000 - 20000 lands the compaction at 140k, inside the local
  # model's window.
  compactionInput = 160000;
  compactionReserved = 20000;

  # The gateway is OpenAI-compatible and unknown to models.dev, so both the
  # transport and the whole model entry are spelled out. The key is ignored --
  # litellm is bound to loopback with no master_key -- but the ai-sdk client
  # refuses to construct without one.
  #
  # The two `limit` numbers do different jobs. `context` is the fallback's
  # window, so nothing here treats the local 160k as the ceiling; `input` is
  # what the auto-compaction threshold is computed from (see `compaction`
  # below), and it is set to the local model's real window.
  gatewayProvider = lib.optionalAttrs hasGateway {
    litellm = {
      npm = "@ai-sdk/openai-compatible";
      name = "LiteLLM (local qwen3.8, OpenRouter fallback)";
      options = {
        baseURL = gatewayUrl;
        apiKey = "unused";
      };
      models.${gatewayModel} = {
        name = "qwen3.8 27B (local, cloud past 145k)";
        tool_call = true;
        reasoning = true;
        limit = {
          context = 1000000;
          input = compactionInput;
          output = 32000;
        };
      };
    };
  };

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

  # pi 0.84.2 bundled an OpenRouter catalog that predates the Pareto router
  # (it knows openrouter/auto, auto-beta, free, and fusion), so the model is
  # added by hand. Custom models are upserted by id into the built-in
  # provider, which keeps its baseUrl and auth.
  #
  # samplingParams is merged verbatim into the request body, which is how the
  # router plugin gets through. Metadata mirrors openrouter/auto: the router
  # advertises a 2M window and variable pricing, so cost is left at zero
  # rather than guessed at.
  #
  # The Qwen side needs no provider of its own: pi ships
  # `qwen-token-plan-individual`, the narrow Personal-Edition catalog on the
  # same compatible-mode endpoint, keyed from QWEN_TOKEN_PLAN_API_KEY (which
  # the wrapper above exports from the same secret as QWEN_API_KEY). Two
  # catalog inaccuracies remain because pi ships a fixed list:
  #   - qwen3.8-flash is served by the subscription but missing from the
  #     individual catalog, so it is upserted below with the metadata pi's
  #     broader qwen-token-plan catalog carries for it.
  #   - deepseek-v4-pro-0813 is in the catalog but not the subscription;
  #     models.json cannot remove built-in models, so it stays listed and
  #     simply errors if selected.
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
    providers."qwen-token-plan-individual".models = [
      {
        id = "qwen3.8-flash";
        name = "Qwen3.8 Flash";
        api = "openai-completions";
        reasoning = true;
        input = [
          "text"
          "image"
        ];
        contextWindow = 1000000;
        maxTokens = 131072;
        compat = {
          thinkingFormat = "qwen";
          supportsDeveloperRole = false;
          supportsStore = false;
          supportsReasoningEffort = true;
        };
        thinkingLevelMap = {
          minimal = null;
          low = null;
          medium = null;
          high = "high";
          xhigh = null;
          max = "max";
        };
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

  # Leave `model` unset: opencode then restores the last model selected in the
  # TUI.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";

    # opencode ships permissive: every tool runs unprompted. Kept that way on
    # purpose -- the prompts were more friction than guardrail here.
    permission = {
      edit = "allow";
      bash = "allow";
      external_directory = "allow";
      webfetch = "allow";
      task = "allow";
    };

    # Compact at 140k rather than riding the gateway's 1M window up: keeps a
    # session on the card, where it is free and fast. The OpenRouter fallback
    # is then only reached by a single turn that overshoots 145k on its own --
    # a huge paste or file read -- not by a conversation growing into it.
    compaction = {
      auto = true;
      reserved = compactionReserved;
    };

    # The binary is a store path it cannot rewrite, and sessions should not
    # leave the machine unless asked for explicitly.
    autoupdate = false;
    share = "disabled";

    # Declarative equivalent of `zg install --target opencode
    # --mcp-transport stdio` from zvec-grep 0.2.1 (install.ts
    # installOpenCodeIntegration). stdio means no daemon to keep up: each
    # opencode session spawns `zg server --stdio`, which manages its own
    # shared daemon. Re-derive both this and the AGENTS.md block below from
    # the new package (run the installer with HOME pointed at a scratch dir)
    # when bumping zvec-grep's version.
    mcp.zvec_grep = {
      type = "local";
      # Resolved from the session PATH; zvec-grep is in home.packages.
      command = [
        "zg"
        "server"
        "--stdio"
      ];
      enabled = true;
      # The installer's --mcp-tool-timeout default: 600s in ms.
      timeout = 600000;
    };

    # Models picked from the TUI's model list (`/models`) live in opencode's
    # own sqlite state, so the last selection survives sessions without
    # fighting the Nix-managed config. Listing this provider is what puts
    # `cloudflare-workers-ai` in that list -- the rest of the
    # model metadata (262k context, tool calls, vision, $0.45/$3.20 per Mtok)
    # comes from models.dev, and the endpoint is built from
    # CLOUDFLARE_ACCOUNT_ID with CLOUDFLARE_API_KEY as the token.
    provider = {
      cloudflare-workers-ai.models.${cfModel} = { };

      # The gateway is OpenAI-compatible and unknown to models.dev, so both the
      # transport and the whole model entry are spelled out here. The key is
      # ignored -- litellm is bound to loopback with no master_key -- but the
      # ai-sdk client refuses to construct without one.
      #
      # `limit.context` is deliberately the *fallback's* window, not the local
      # 160k: it is what opencode counts against before it decides to compact,
      # and compacting at 160k would defeat the point of having a 1M-token
      # deployment waiting behind the proxy. Sessions now compact only when
      # OpenRouter's copy is also full.

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
      openrouter.models.${codingModel} = {
        reasoning = true;
        options = {
          plugins = paretoPlugin;
          reasoning.effort = "medium";
        };
      };
    }
    // gatewayProvider
    // qwenProvider;
  };

  # The guidance block `zg install` writes to ~/.config/opencode/AGENTS.md,
  # copied verbatim from its 0.2.1 output (opencode loads the config-dir
  # AGENTS.md globally; the markers let the installer's uninstall find it too
  # if one ever runs against this file).
  xdg.configFile."opencode/AGENTS.md".text = ''
    <!-- ZVEC_GREP_START -->
    ## zvec-grep

    Choose the evidence source before the retrieval mode.

    ### Workspace evidence
    - Use the current workspace as the evidence source when the user asks about local material, prior context establishes it as relevant, or the question concerns how the current project works—even if the workspace is not mentioned explicitly.
    - A workspace may contain any mix of code, documents, configuration, and data.
    - Do not use workspace retrieval for unrelated open-world questions, current external facts, or web content that does not depend on local evidence.

    ### Retrieval routing
    - When an exact word, phrase, name, date, identifier, filename, path, configuration key, error message, source fragment, literal, or regex is known and locating its occurrences is sufficient, use `zvec_grep_zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg`.
    - Use `zvec_grep_zvec_grep_search` when wording or location is unknown, or when the answer requires semantic, conceptual, fuzzy, or paraphrase discovery; relationships, chronology, causality, architecture, or data or control flow; or comparison or synthesis across files, sections, or documents.
    - For a mixed task with exact anchors that still requires relationships or cross-file synthesis, call `zvec_grep_zvec_grep_search` with the concept and anchors, then use `zvec_grep_zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg` for focused follow-up.
    - When no sufficient exact anchor is available and the user asks whether conceptually related material exists locally, make at most one focused `zvec_grep_zvec_grep_search` probe using the question plus distinctive names, dates, or terms. This probe does not apply to exact quotations, configuration keys, filenames, regexes, or exhaustive occurrence requests. Continue only when results are relevant; otherwise stop and report that the indexed workspace did not establish the answer.
    - Before broad file reads or delegating workspace discovery, use the appropriate search route. Do not delegate solely to locate material, and stop when the evidence is sufficient.

    ### Search evidence
    - Search results include bounded source snippets. Treat a sufficient snippet as already-read evidence, and read a cited file only when a required detail falls outside the snippet.

    ### Freshness and index lifecycle
    - Pass a daemon-visible absolute `root` on every zvec-grep workspace call.
    - Read `freshness` and `background_refresh` from search results without a status preflight.
    - When results are `served_from_current_index`, use them when sufficient instead of waiting for the background refresh.
    - If the index is missing but exact or regex lookup can answer the task, use `zvec_grep_zvec_grep_rg` when it is listed by the current host; otherwise native Grep or `rg`.
    - Creating, rebuilding, or dropping a persistent index requires an explicit user request or authorization; never do so silently.

    <!-- ZVEC_GREP_END -->
  '';

}
