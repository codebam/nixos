{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:

let
  # The per-agent credentials live as individual sops keys
  # (desktop/configuration/sops.nix). Each wrapper below runs this script at
  # launch; it exports only the names in secretVars, so unrelated tokens in
  # /run/secrets never reach an interactive shell. sops.templates."hermes-env"
  # reassembles the base set plus the token-plan keys Hermes needs, as a file
  # for the Hermes agent itself, so the deleted hand-maintained blob stays a
  # generated artifact.
  secretVars = {
    OPENROUTER_API_KEY = "openrouter-api-key";
    CONTEXT7_API_KEY = "context7-api-key";
    CLOUDFLARE_ACCOUNT_ID = "cloudflare-account-id";
    CLOUDFLARE_API_KEY = "cloudflare-api-key";
  };
  secretVarPairs = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: secret: "${name}:${secret}") secretVars
  );
  loadKey = pkgs.writeShellScript "agent-load-env" ''
    for pair in ${secretVarPairs}; do
      name=''${pair%%:*}
      secret=''${pair#*:}
      file=/run/secrets/$secret
      if [ -r "$file" ]; then
        value=$(cat "$file")
        if [ -n "$value" ]; then export "$name=$value"; fi
      fi
    done

    qwen_secret=/run/secrets/qwen-api-key
    if [ -r "$qwen_secret" ]; then
      QWEN_API_KEY=$(cat "$qwen_secret")
      export QWEN_API_KEY
      # pi resolves its built-in qwen-token-plan* providers from this exact
      # name (env-api-keys.ts envMap); same plan key, second name.
      QWEN_TOKEN_PLAN_API_KEY=$QWEN_API_KEY
      export QWEN_TOKEN_PLAN_API_KEY
    fi

    # DeepSeek direct API key for the deepseek provider in opencode.json.
    deepseek_secret=/run/secrets/deepseek-api-key
    if [ -r "$deepseek_secret" ]; then
      DEEPSEEK_API_KEY=$(cat "$deepseek_secret")
      export DEEPSEEK_API_KEY
    fi

    # OpenCode Go. models.dev gives both `opencode` (Zen) and `opencode-go` the
    # same env entry -- OPENCODE_API_KEY -- so exporting it once makes the Go
    # models show up as opencode-go/<model-id> in the picker with no provider
    # block in opencode.json: the catalog already carries all 35 models, their
    # limits and their per-model npm package. The side effect is that the Zen
    # provider is offered too, and this key is not a Zen balance, so a Zen model
    # there is a request that fails.
    go_secret=/run/secrets/opencode-go-api-key
    if [ -r "$go_secret" ]; then
      OPENCODE_API_KEY=$(cat "$go_secret")
      export OPENCODE_API_KEY
    fi

    # CrofAI's OpenAI-compatible gateway, used by the CrofAI provider in
    # opencode.json, pi's models.json, and dsh's llm-pi-ai route below.
    # Exported under the name CrofAI's own docs use so a plain shell works too.
    crofai_secret=/run/secrets/crofai-api-key
    if [ -r "$crofai_secret" ]; then
      CROFAI_API_KEY=$(cat "$crofai_secret")
      export CROFAI_API_KEY
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

  # Union Alpha, the free stealth model OpenCode and OpenRouter both carry for
  # a limited time. OpenCode's own gateway serves it as `union-alpha`;
  # OpenRouter serves the same weights as `stealth/union-alpha`. The routes
  # differ beyond the id: the OpenCode copy reports reasoning support, while
  # OpenRouter's copy advertises no reasoning parameter. Shared metadata:
  # 262144 context, 131072 output, text+image input, $0.
  #
  # OpenCode discovers both from models.dev, but the declarations in
  # opencode.json below pin the free metadata so a stale catalog cache cannot
  # drop the model. pi-ai 0.85.1's bundled opencode-go and OpenRouter catalogs
  # predate it, so pi gets hand-declared upserts in models.json and dsh gets
  # dedicated llm-pi-ai routes in settings.yaml, where a `models` list on the
  # shared catalog routes would replace their whole mixed-protocol catalogs.
  # The OpenCode Zen copy is not declared for pi or dsh: its free tier answers
  # raw API calls with MissingSessionID and is usable only inside the OpenCode
  # client, while the exported OPENCODE_API_KEY authenticates the Go route from
  # any harness.
  unionAlpha = {
    opencodeId = "union-alpha";
    openrouterId = "stealth/union-alpha";
    contextWindow = 262144;
    maxTokens = 131072;
  };

  # The opencode.json model shape shared by both OpenCode provider ids
  # (`opencode` Zen and `opencode-go`): models.dev gives them the same entry.
  unionAlphaOpencodeModel = {
    name = "Union Alpha Free";
    reasoning = true;
    tool_call = true;
    attachment = true;
    limit = {
      context = unionAlpha.contextWindow;
      output = unionAlpha.maxTokens;
    };
    modalities = {
      input = [
        "text"
        "image"
      ];
      output = [ "text" ];
    };
  };

  # Qwen Cloud Token Plan, following the vendor's opencode recipe
  # (docs.qwencloud.com/developer-guides/clients-and-developer-tools/opencode):
  # the Anthropic Messages endpoint rather than the OpenAI-compatible one.
  # The provider id stays `qwen` so existing `qwen/<model>` selections and
  # session history resolve unchanged.
  #
  # The model set below is the Personal Edition chat models these harnesses
  # use. QwenCloud's supported-model table (token-plan/personal) also lists
  # image/video/audio models (wan2.7-image{,-pro}, qwen-image-3.0-pro,
  # qwen-audio-3.0-*), but those answer neither chat-completions nor messages
  # requests (image-generation, TTS, and realtime APIs respectively), so they
  # have no place in either harness. deepseek-v4.1-flash was added 2026-09-13;
  # pi-ai 0.85.1's bundled catalog predates it, so the pi and dsh catalogs
  # below declare it by hand too. Limits use the 983616-token chat window and
  # per-model output caps; thinking is pinned the way the recipe pins it
  # (effort for the 3.8 pair, a fixed 8192-token budget for 3.7/3.6/glm,
  # default-on for the deepseek pair).
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
        "deepseek-v4.1-flash" = {
          name = "DeepSeek V4.1 Flash";
          reasoning = true;
          tool_call = true;
          limit = {
            context = 983616;
            output = 384000;
          };
          modalities = {
            input = [
              "text"
              "image"
            ];
            output = [ "text" ];
          };
        };
      };
    };
  };

  # CrofAI's /v1/models catalog (live 2026-09-12), kept as one canonical list
  # because all three harnesses need it and none can discover it: models.dev
  # has no CrofAI provider and pi-ai ships no such catalog, so opencode, pi,
  # and dsh's hand-declared llm-pi-ai route each project this list into their
  # own shape. `reasoning` mirrors the API's reasoning_effort flag (the two
  # greg-2-* models are the only ones without it); `vision` mirrors
  # /pricing_api's vision_models -- deepseek-v4-flash-vision-exp is absent
  # there and 400s when an image is sent with reasoning_effort, so it stays
  # text-only here despite its id. cost is USD per million tokens; cacheRead is
  # CrofAI's cache_prompt rate and CrofAI bills no separate cache-write rate.
  crofModels = [
    {
      id = "deepseek-v4.1-flash";
      name = "DeepSeek V4.1 Flash";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.10;
        output = 0.50;
        cacheRead = 0.003;
        cacheWrite = 0;
      };
    }
    {
      id = "deepseek-v4-pro-0813";
      name = "DeepSeek V4 Pro 0813";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.35;
        output = 0.80;
        cacheRead = 0.01;
        cacheWrite = 0;
      };
    }
    {
      id = "deepseek-v4-flash-vision-exp";
      name = "DeepSeek V4 Flash Vision (exp)";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.08;
        output = 0.20;
        cacheRead = 0.007;
        cacheWrite = 0;
      };
    }
    {
      id = "deepseek-v4-flash-0731";
      name = "DeepSeek V4 Flash 0731";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.07;
        output = 0.10;
        cacheRead = 0.003;
        cacheWrite = 0;
      };
    }
    {
      id = "kimi-k3";
      name = "Kimi K3";
      context = 1000000;
      output = 262144;
      reasoning = true;
      vision = false;
      cost = {
        input = 2.00;
        output = 8.00;
        cacheRead = 0.25;
        cacheWrite = 0;
      };
    }
    {
      id = "kimi-k3-eco";
      name = "Kimi K3 (Eco)";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 1.00;
        output = 4.00;
        cacheRead = 0.10;
        cacheWrite = 0;
      };
    }
    {
      id = "kimi-k2.7-code";
      name = "Kimi K2.7 Code";
      context = 262144;
      output = 262144;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.55;
        output = 2.25;
        cacheRead = 0.05;
        cacheWrite = 0;
      };
    }
    {
      id = "kimi-k2.6";
      name = "Kimi K2.6";
      context = 262144;
      output = 262144;
      reasoning = true;
      vision = true;
      cost = {
        input = 0.50;
        output = 1.99;
        cacheRead = 0.05;
        cacheWrite = 0;
      };
    }
    {
      id = "glm-5.3";
      name = "GLM 5.3";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.40;
        output = 1.40;
        cacheRead = 0.06;
        cacheWrite = 0;
      };
    }
    {
      id = "glm-5.3-flash";
      name = "GLM 5.3 Flash";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.07;
        output = 0.22;
        cacheRead = 0.01;
        cacheWrite = 0;
      };
    }
    {
      id = "glm-5.2";
      name = "GLM 5.2";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.30;
        output = 1.05;
        cacheRead = 0.05;
        cacheWrite = 0;
      };
    }
    {
      id = "greg-2-ultra";
      name = "Greg 2 Ultra";
      context = 229376;
      output = 229376;
      reasoning = false;
      vision = false;
      cost = {
        input = 3.00;
        output = 10.00;
        cacheRead = 0.50;
        cacheWrite = 0;
      };
    }
    {
      id = "greg-2-super";
      name = "Greg 2 Super";
      context = 229376;
      output = 229376;
      reasoning = false;
      vision = false;
      cost = {
        input = 1.50;
        output = 5.00;
        cacheRead = 0.25;
        cacheWrite = 0;
      };
    }
    {
      id = "mimo-v2.5-pro";
      name = "MiMo-V2.5-Pro";
      context = 1000000;
      output = 131072;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.40;
        output = 0.80;
        cacheRead = 0.003;
        cacheWrite = 0;
      };
    }
    {
      id = "gemma-4-31b-it";
      name = "Gemma 4 31B";
      context = 262144;
      output = 262144;
      reasoning = true;
      vision = true;
      cost = {
        input = 0.10;
        output = 0.30;
        cacheRead = 0.02;
        cacheWrite = 0;
      };
    }
    {
      id = "qwen3.8-27b";
      name = "Qwen3.8 27B";
      context = 262144;
      output = 262144;
      reasoning = true;
      vision = false;
      cost = {
        input = 0.09;
        output = 0.30;
        cacheRead = 0.01;
        cacheWrite = 0;
      };
    }
    {
      id = "qwen3.5-9b";
      name = "Qwen3.5 9B";
      context = 262144;
      output = 262144;
      reasoning = true;
      vision = true;
      cost = {
        input = 0.04;
        output = 0.15;
        cacheRead = 0.008;
        cacheWrite = 0;
      };
    }
  ];

  # opencode's model shape. A model config with no models.dev entry defaults
  # tool_call to true, so only reasoning and the vision attachment capability
  # need stating; `modalities` is what drives the input capabilities in the TUI.
  crofOpencodeModels = builtins.listToAttrs (
    map (model: {
      name = model.id;
      value = {
        inherit (model) name reasoning;
        limit = {
          inherit (model) context output;
        };
        cost = {
          input = model.cost.input;
          output = model.cost.output;
          cache_read = model.cost.cacheRead;
          cache_write = model.cost.cacheWrite;
        };
      }
      // lib.optionalAttrs model.vision {
        attachment = true;
        modalities = {
          input = [
            "text"
            "image"
          ];
          output = [ "text" ];
        };
      };
    }) crofModels
  );

  crofOpencodeProvider = {
    npm = "@ai-sdk/openai-compatible";
    name = "CrofAI";
    options = {
      baseURL = "https://crof.ai/v1";
      apiKey = "{env:CROFAI_API_KEY}";
    };
    models = crofOpencodeModels;
  };

  # pi's models.json shape. crofai is a new provider rather than an override of
  # a built-in, so it names api and baseUrl itself. The compat block is not
  # optional: pi's baseURL detection cannot recognise the endpoint and would
  # otherwise send the `developer` role and `store`, which CrofAI does not take.
  crofPiModels = map (
    model:
    {
      inherit (model) id name reasoning;
      input =
        if model.vision then
          [
            "text"
            "image"
          ]
        else
          [ "text" ];
      contextWindow = model.context;
      maxTokens = model.output;
      cost = {
        input = model.cost.input;
        output = model.cost.output;
        cacheRead = model.cost.cacheRead;
        cacheWrite = model.cost.cacheWrite;
      };
    }
    // lib.optionalAttrs model.reasoning {
      # CrofAI takes reasoning_effort low/medium/high/none only; hide pi's
      # minimal/xhigh/max rather than letting them reach the wire.
      thinkingLevelMap = {
        off = "none";
        minimal = null;
        low = "low";
        medium = "medium";
        high = "high";
        xhigh = null;
        max = null;
      };
    }
  ) crofModels;

  # dsh's llm-pi-ai route needs the same catalog as YAML inside the managed
  # settings fragment below. Emit one list entry per canonical model so the
  # route definition itself stays readable, and let the route-level compat
  # cover every model.
  crofDshModelYaml =
    model:
    lib.concatStringsSep "\n" (
      [
        "        - id: ${model.id}"
        "          name: ${model.name}"
        "          contextWindow: ${toString model.context}"
        "          maxTokens: ${toString model.output}"
        "          input:"
        "            - text"
      ]
      ++ lib.optional model.vision "            - image"
      ++ (
        if model.reasoning then
          [
            "          reasoningEfforts:"
            "            off: none"
            "            low: low"
            "            medium: medium"
            "            high: high"
          ]
        else
          [ "          reasoningEfforts: false" ]
      )
    );

  crofDshModelsYaml = lib.concatStringsSep "\n" (
    [ "      models:" ] ++ map crofDshModelYaml crofModels
  );

  # Headroom opencode keeps before it auto-compacts; see `compaction` below.
  compactionReserved = 20000;

  opencode = pkgs.symlinkJoin {
    name = "opencode-wrapped-${pkgs.opencode.version}";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode --run '. ${loadKey}'
    '';
  };

  # Desktop front-end of the same agent. It reads the shared
  # ~/.config/opencode/opencode.json (written below), whose providers key off
  # `{env:QWEN_API_KEY}` and OPENROUTER_API_KEY. Launched from a .desktop entry
  # it inherits no shell environment, so wrap it with the same loadKey the CLI
  # uses: symlinkJoin keeps the package's share/applications, and the bundled
  # Exec=opencode-desktop resolves to this wrapped binary on PATH.
  opencode-desktop = pkgs.symlinkJoin {
    name = "opencode-desktop-wrapped-${pkgs.opencode-desktop.version}";
    paths = [ pkgs.opencode-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode-desktop --run '. ${loadKey}'
    '';
  };

  # The beta desktop is the build that pairs with opencode2 and hosts the
  # integrated browser the agent's browser.* tools attach to; the stable
  # nixpkgs package above does not. Wrapped with loadKey for the same reason:
  # a .desktop launch inherits no shell environment, and it needs the same
  # provider secrets.
  opencode-desktop-beta = pkgs.symlinkJoin {
    name = "opencode-desktop-beta-wrapped-${pkgs.opencode-desktop-beta.version}";
    paths = [ pkgs.opencode-desktop-beta ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode-desktop-beta --run '. ${loadKey}'
    '';
  };

  # The beta channel of the same agent (npm @opencode/cli, upstream command
  # `opencode2`), built from the registry binaries in pkgs/opencode-cli.nix.
  # Wrapped with loadKey like the stable one so both see the same provider
  # secrets; it stays a separate binary so the nixpkgs `opencode` is
  # untouched until the beta proves itself.
  #
  # OPENCODE_DISABLE_AUTOUPDATE: the beta polls
  # opencode.ai/update/api/<platform>/<arch>/npm on a 10-minute interval and,
  # when it recognises its own install method (npm/pnpm/bun/yarn -g), offers to
  # reinstall itself. A /nix/store binary is read-only and pkged here, so both
  # the poll and the offer are noise; the stable nixpkgs opencode wrapper sets
  # the same variable. ripgrep joins PATH because opencode2 shells out to `rg`
  # for grep/search and, unlike the stable package, gets no wrapper that names
  # it for it.
  opencode2 = pkgs.symlinkJoin {
    name = "opencode2-wrapped-${pkgs.opencode-cli.version}";
    paths = [ pkgs.opencode-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode2 \
        --run '. ${loadKey}' \
        --prefix PATH : ${lib.makeBinPath [ pkgs.ripgrep ]} \
        --set OPENCODE_DISABLE_AUTOUPDATE true
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

  # DeepSeek Harness (`dsh`), packaged in pkgs/dsh.nix. Wrapped with loadKey for
  # the same reason as opencode and pi: its llm-pi-ai `opencode-go` route names
  # the OPENCODE_API_KEY credential reference, and the credential store falls
  # back to the launch environment, so exporting the key here is what makes the
  # route authenticate without a secret in settings.yaml. dsh's own wrapper
  # already adds --expose-internals for its HMR plugin; wrapProgram preserves
  # that and only prepends the environment load.
  dsh = pkgs.symlinkJoin {
    name = "dsh-wrapped-${pkgs.dsh.version}";
    paths = [ pkgs.dsh ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/dsh --run '. ${loadKey}'
    '';
  };

  # The web profile's persistent front door. dsh refuses --host 0.0.0.0, so
  # the server itself stays on loopback; Tailscale Serve (see
  # desktop/configuration/systemd.nix) owns the tailnet-facing TLS endpoint.
  # 8443 rather than 443 because nginx already binds wildcard 80/443 here.
  dshWebBackendPort = 3080;
  dshWebProxyPort = 8443;

  # dsh-web is a desktop concern: the matching Tailscale Serve unit lives in
  # desktop/configuration/systemd.nix, and the helper only makes sense where
  # that service runs.
  isDesktop = osConfig.networking.hostName == "nixos-desktop";

  # The OpenSandbox user service, osb wrappers, and the dsh container world
  # only exist where rootless podman does (desktop and laptop).
  podmanEnabled = osConfig.virtualisation.podman.enable or false;

  # The @codebam/dsh-opensandbox world replacement: on, dsh's execution world
  # (ctx.subprocess/ctx.sandbox) is OpenSandbox containers instead of the host.
  # The plugin reaches execd through each sandbox's direct published endpoint --
  # the official SDK default (use_server_proxy=false) -- because the pinned
  # server image's own API-proxy WebSocket route never completes its handshake
  # and then crashes reporting that on a websockets API mismatch. Verified
  # end-to-end against the live server in both policy modes: terminal startup,
  # PTY command I/O, and the model-facing bash tool's one-shot collect path.
  dshContainerWorld = true;

  # Per-process escape hatch for the row swap below. dsh treats every DSH_*
  # name as bootstrap-only, so a repository's .env cannot set it -- it has to
  # come from the launching environment. Any non-empty value boots dsh on the
  # built-in bwrap/Landlock world for that process; unset or empty keeps the
  # OpenSandbox world. The `dsh-no-opensandbox` wrapper is the one-command
  # form. This fallback is deliberately outside the hardened mount boundary.
  dshNoOpenSandboxEnv = "DSH_NO_OPENSANDBOX";
  dshUseOpenSandboxJs = "!process.env.${dshNoOpenSandboxEnv}";
  dshNoOpenSandboxJs = "Boolean(process.env.${dshNoOpenSandboxEnv})";

  # The default dsh OpenSandbox world is the untrusted-agent tier: /nix/store
  # read-only for toolchain binaries, no host daemon, no credential mounts,
  # and no forwarded GH_TOKEN/SSH_AUTH_SOCK. A human launches
  # `dsh-host-access` when a reviewed task genuinely needs those host
  # bridges; the profile patch reads this variable at load time and widens
  # only the explicit mount/env grants. The filesystem fence and the mount
  # table stay in force in both tiers.
  dshHostAccessEnv = "DSH_OPEN_SANDBOX_HOST_ACCESS";
  dshHostAccessJs = "process.env.${dshHostAccessEnv} === '1'";
  dshStrictReadOnlyMounts = [ "/nix/store" ];
  dshHostAccessReadOnlyMounts = dshStrictReadOnlyMounts ++ [
    "/etc/nix"
    "/nix/var/nix/daemon-socket"
    "/nix/var/nix/profiles"
    "${config.home.homeDirectory}/.config/git"
    "${config.home.homeDirectory}/.config/dsh-sandbox"
    "${config.home.homeDirectory}/.gnupg"
    "/run/user/1000/gnupg"
  ];
  # Harness-owned reads ctx.fs needs even though they are not sandbox mounts:
  # user skills and the user-global AGENTS.md. Keep this list narrow.
  dshTrustedReadPaths = [
    "${config.home.homeDirectory}/.dsh/AGENTS.md"
    "${config.home.homeDirectory}/.dsh/skills"
    "${config.home.homeDirectory}/.agents/skills"
  ];
  # The Debian image ships no system CA store. These four names are read by
  # curl, git, Go, and nix's TLS stack respectively.
  dshCaEnv = {
    NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };
  dshHostAccessEnvVars = dshCaEnv // {
    GIT_CONFIG_GLOBAL = "${config.home.homeDirectory}/.config/dsh-sandbox/gitconfig";
  };

  # Host roots under which dsh sessions may open a project. `workspaceRoot`
  # (the dsh process cwd) is always allowed; these add the dsh-web project
  # picker roots. Only the exact session root becomes a bind mount, so a
  # sibling project is visible to harness discovery at most, never a workdir
  # mount.
  dshWorkspaceParents = [
    "${config.home.homeDirectory}/Documents/git"
    "/persistent"
    "/tmp"
  ];
  # The dsh plugin's ctx.fs fence and the OpenSandbox server-side bind guard
  # must name the same credential/control paths; keep them on one definition.
  dshProtectedHostPaths =
    (import ./opensandbox-paths.nix { home = config.home.homeDirectory; }).readonlyHostPaths;

  # Both interactive dsh surfaces keep the one hand-written patch row they
  # carried before the sandbox providers changed: the hand-declared OpenCode Go
  # routes (`opencode-go-deepseek`, `opencode-go-union-alpha`) must be named or
  # dsh attaches no x-opencode-session header and OpenCode Go answers 400.
  #
  # dshContainerWorld (see above) also swaps the execution world:
  # @codebam/dsh-opensandbox registers ctx.subprocess, ctx.sandbox, and
  # ctx.fs, so the two local providers and dsh's host-fs provider are
  # disabled and the stock bash, terminal, search, and file tools run over
  # the OpenSandbox mount table. While it is off -- or a process sets
  # DSH_NO_OPENSANDBOX, see below -- every host keeps the built-in
  # bwrap/Landlock sandbox rows and the host-fs provider.
  dshProfilePatch = ''
    # Your patch layer for this dsh profile, applied after every bundle layer:
    # a top-level YAML array of loader patch entries (id-targeted config
    # overrides, disables, and insert lists; `!!js` expressions allowed).
    #
    # Managed by home-manager (home/agents.nix); make changes in the flake,
    # not under ~/.dsh.

    # `opencode-go-deepseek` and `opencode-go-union-alpha` are hand-declared
    # pi-ai routes, not the catalog ids dsh-opencode-session defaults to
    # (opencode/opencode-go), so the plugin has to be told about them or it
    # attaches no x-opencode-session header and OpenCode Go answers 400
    # MissingSessionID.
    - id: opencode-go-session-header
      config:
        providers:
          - opencode
          - opencode-go
          - opencode-go-deepseek
          - opencode-go-union-alpha
  ''
  + lib.optionalString dshContainerWorld ''
    # dsh-opensandbox: replace the host execution world with
    # OpenSandbox containers. The plugin registers ctx.subprocess,
    # ctx.sandbox, and ctx.fs, so both local providers and dsh's host-fs
    # provider are disabled; the stock bash, terminal, search, and file tools
    # then run over the container world and its mount table. `apiKeyFile` is
    # the per-boot key home/opensandbox.nix generates under the user runtime
    # dir; the plugin reads it lazily, so login ordering does not matter.
    #
    # The default configuration is the untrusted-agent tier: /nix/store is
    # visible read-only for toolchain binaries, and no host credentials,
    # daemon socket, or arbitrary host path is. A human runs
    # `dsh-host-access` for reviewed work that needs those host bridges; it
    # is a separate command and never the default.
    #
    # DSH_NO_OPENSANDBOX (exported by dsh-no-opensandbox) flips these
    # load-time expressions: the local rows come back, dsh's host fs provider
    # stays mounted, and the plugin row is skipped for that process.
    - id: subprocess
      disabled: !!js "${dshUseOpenSandboxJs}"

    - id: sandbox
      disabled: !!js "${dshUseOpenSandboxJs}"

    # dsh's shipped fs backend fences writes but deliberately leaves reads
    # unconfined (the host filesystem is normally the execution world). The
    # plugin's ctx.fs replaces it with the same mount table the container
    # uses.
    - id: fs-sandbox
      disabled: !!js "${dshUseOpenSandboxJs}"

    - insert:
        - id: opensandbox-world
          name: ${config.home.homeDirectory}/.dsh/profiles/opensandbox/index.mjs
          disabled: !!js "${dshNoOpenSandboxJs}"
          config:
            apiKeyFile: /run/user/1000/opensandbox/api-key
            domain: 127.0.0.1:8090
            image: docker.io/library/debian@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132
            requestTimeoutMs: 900000
            timeoutSeconds: 43200

            # Only the mount table, env, and forwarded names change between
            # the default tier and an explicit `dsh-host-access` launch; the
            # filesystem fence and dynamic-mount commands stay the same.
            # Block scalars keep the JSON colons out of YAML parsing.
            extraReadOnlyMounts: !!js >-
              ${dshHostAccessJs}
              ? ${builtins.toJSON dshHostAccessReadOnlyMounts}
              : ${builtins.toJSON dshStrictReadOnlyMounts}
            extraWritableMounts: []
            trustedReadPaths: ${builtins.toJSON dshTrustedReadPaths}
            workspaceParents: ${builtins.toJSON dshWorkspaceParents}
            protectedPaths: ${builtins.toJSON dshProtectedHostPaths}
            allowDynamicMounts: true
            provideFilesystem: true

            # Host-access adds GIT_CONFIG_GLOBAL for the sandbox git config;
            # the default tier carries only the CA bundle names every network
            # tool needs.
            env: !!js >-
              ${dshHostAccessJs}
              ? ${builtins.toJSON dshHostAccessEnvVars}
              : ${builtins.toJSON dshCaEnv}

            # Host-prepared credentials, only in the host-access tier; unset
            # names are skipped rather than blanked. The default tier forwards
            # nothing.
            forwardEnv: !!js >-
              ${dshHostAccessJs}
              ? ["SSH_AUTH_SOCK", "GH_TOKEN"]
              : []
  ''
  + lib.optionalString dshContainerWorld ''
    # @codebam/dsh-tool-nu: the model-facing `nu` tool, beside `bash`. It
    # consumes the mounted ctx.shell provider, so do NOT disable or replace
    # bash-sandbox / tool-bash; the stock bash tool and world are unchanged.
    # Works in the OpenSandbox world and in a dsh-no-opensandbox session,
    # because both leave a bash executor mounted as ctx.shell.
    - insert:
        - id: tool-nu
          name: ${config.home.homeDirectory}/.dsh/profiles/tool-nu/index.mjs
          disabled: !!js process.platform === 'win32'
          config:
            executable: ${pkgs.nushell}/bin/nu
            enableRunInBackground: true
  '';

  # Host credentials prepared only for `dsh-host-access`, never for the
  # default dsh session: gh's keyring token becomes GH_TOKEN, SOPS is pointed
  # at the YubiKey age identity plugin, SSH falls back to the gpg-agent SSH
  # socket when the login environment did not export one, and GPG gets a real
  # TTY for pinentry when there is one.
  credentialEnv = pkgs.writeShellScript "agent-credential-env" ''
    if [ -z "''${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
      GH_TOKEN=$(gh auth token 2>/dev/null || true)
      if [ -n "$GH_TOKEN" ]; then export GH_TOKEN; fi
    fi
    export SOPS_AGE_KEY_CMD='age-plugin-yubikey -i'
    if [ -z "''${SSH_AUTH_SOCK:-}" ]; then
      for candidate in "/run/user/$(id -u)/gnupg/S.gpg-agent.ssh" "$HOME/.gnupg/S.gpg-agent.ssh"; do
        if [ -S "$candidate" ]; then
          SSH_AUTH_SOCK=$candidate
          export SSH_AUTH_SOCK
          break
        fi
      done
    fi
    if [ -t 0 ] && [ -z "''${GPG_TTY:-}" ]; then
      GPG_TTY=$(tty 2>/dev/null || true)
      if [ -n "$GPG_TTY" ]; then export GPG_TTY; fi
    fi
  '';

  # The host-access tier mounts the host keyring read-only -- a sandbox must
  # not be able to edit it -- but gpg will not sign without creating lock files
  # in its homedir (verified: "failed to create temporary file ... Permission
  # denied", then "no default secret key"). This wrapper gives it a writable
  # copy inside the container and points every agent socket at the host user's
  # gpg-agent, so the private key itself never leaves the YubiKey. The sandbox
  # git config below points gpg.program here.
  #
  # GnuPG 2.1+ does not talk to $GNUPGHOME/S.gpg-agent for a custom homedir; it
  # asks gpgconf for $XDG_RUNTIME_DIR/gnupg/d.<hash>/S.gpg-agent. Linking only
  # the homedir paths left that runtime path empty, so gpg autostarted a local
  # sandbox agent whose scdaemon cannot see USB -- and every signed commit
  # failed through it ("Not confirmed"). Re-link both paths on every call, and
  # pass --no-autostart so a missing host agent fails loudly instead of silently
  # falling back to an agent without the card.
  dshSandboxGpg = pkgs.writeShellApplication {
    name = "dsh-sandbox-gpg";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnupg
    ];
    text = ''
      set -eu
      umask 077
      source_home=''${DSH_SANDBOX_GNUPGHOME:-/home/codebam/.gnupg}
      agent_dir=''${DSH_SANDBOX_GPG_AGENT_DIR:-/run/user/1000/gnupg}
      work=''${TMPDIR:-/tmp}/dsh-sandbox-gnupg
      if [ ! -d "$work" ]; then
        mkdir -p "$work"
        chmod 700 "$work"
        cp -a "$source_home/." "$work/" 2>/dev/null || true
      fi

      link_socket() {
        if [ -S "$agent_dir/$1" ] && [ -n "$2" ]; then
          mkdir -p "$(dirname "$2")"
          chmod 700 "$(dirname "$2")"
          ln -sfn "$agent_dir/$1" "$2"
        fi
      }

      # Legacy homedir paths (older clients); harmless on GnuPG 2.4.
      link_socket S.gpg-agent "$work/S.gpg-agent"
      link_socket S.gpg-agent.ssh "$work/S.gpg-agent.ssh"

      # What GnuPG 2.1+ actually connects to for this custom homedir.
      runtime_socket=$(GNUPGHOME="$work" gpgconf --list-dirs agent-socket)
      runtime_ssh_socket=$(GNUPGHOME="$work" gpgconf --list-dirs agent-ssh-socket)
      link_socket S.gpg-agent "$runtime_socket"
      link_socket S.gpg-agent.ssh "$runtime_ssh_socket"

      export GNUPGHOME="$work"
      exec gpg --no-autostart "$@"
    '';
  };

  # Desktop-only dsh command: source the model API keys outside the harness,
  # then run the upstream binary. Host credentials are deliberately NOT loaded
  # here: the default session is the untrusted-agent tier and the OpenSandbox
  # profile forwards nothing. Use `dsh-host-access` when reviewed work really
  # needs the host daemon or credentials. Starting in $HOME is still refused:
  # it would make the whole home directory the writable workspace.
  dshSandboxed = pkgs.writeShellApplication {
    name = "dsh";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gh
    ];
    text = ''
      set -eu
      # shellcheck source=/dev/null
      . ${loadKey}
      case "$PWD" in
        "$HOME")
          echo "dsh: refusing to start in \$HOME; cd into a project directory first" >&2
          exit 2
          ;;
        "$HOME"/* | /persistent/* | /tmp | /tmp/*) ;;
        *)
          echo "dsh: refusing unsupported workspace $PWD; start under \$HOME, /persistent, or /tmp" >&2
          exit 2
          ;;
      esac
      exec ${lib.getExe pkgs.dsh} "$@"
    '';
  };

  dshInstalled = if isDesktop then dshSandboxed else dsh;

  # One-command form of the DSH_NO_OPENSANDBOX escape hatch, installed only
  # where the OpenSandbox world exists. It just exports the launch variable;
  # the profile patch above does the switching, so every dsh subcommand (`web`,
  # `--profile`, `plugin`) keeps its normal argv. The result is still a
  # sandbox -- dsh's built-in bwrap/Landlock world, not the host shell.
  dshNoOpenSandbox = pkgs.writeShellApplication {
    name = "dsh-no-opensandbox";
    text = ''
      set -eu
      export ${dshNoOpenSandboxEnv}=1
      exec ${lib.getExe' dshInstalled "dsh"} "$@"
    '';
  };

  # Explicit human-launched elevated tier. It restores the host Nix daemon
  # socket, the git/GPG agent mounts, and the forwarded GH_TOKEN/SSH_AUTH_SOCK
  # for reviewed build/push work. The OpenSandbox mount fence and ctx.fs fence
  # still apply, so this widens only the host bridges the profile patch names;
  # it does not restore the old unconfined host fs reads.
  dshHostAccess = pkgs.writeShellApplication {
    name = "dsh-host-access";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gh
    ];
    text = ''
      set -eu
      # shellcheck source=/dev/null
      . ${loadKey}
      # shellcheck source=/dev/null
      . ${credentialEnv}
      export ${dshHostAccessEnv}=1
      echo "dsh-host-access: host Nix daemon and agent credentials are inside this sandbox session" >&2
      exec ${lib.getExe' dshInstalled "dsh"} "$@"
    '';
  };

  # Tailscale Serve forwards the browser's original Host header, so dsh's
  # browser-trust fence has to trust the MagicDNS authority. Resolve it at
  # start instead of embedding <host>.<tailnet>.ts.net in this repo; Serve
  # terminates TLS on dshWebProxyPort, so that is the exact authority the
  # browser sends.
  dshWebServe = pkgs.writeShellApplication {
    name = "dsh-web-serve";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gh
      pkgs.jq
      pkgs.tailscale
    ];
    text = ''
      set -eu
      # shellcheck source=/dev/null
      . ${loadKey}
      authority=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')
      exec ${lib.getExe pkgs.dsh} web \
        --host 127.0.0.1 \
        --port ${toString dshWebBackendPort} \
        --no-open \
        --trusted-host "$authority:${toString dshWebProxyPort}"
    '';
  };

  # dsh only prints its loopback URL; the browser's first visit has to carry
  # the per-process launch token to the Serve authority. The signed session
  # cookie it mints persists across dsh restarts (the signing secret lives in
  # ~/.dsh/.credentials.yaml), so this is a recovery path, not a daily command.
  #
  # The URL line is emitted by the dsh process itself; select the current
  # systemd invocation instead of filtering on MainPID so the token still
  # resolves across restarts and wrapper changes.
  dshWebUrl = pkgs.writeShellApplication {
    name = "dsh-web-url";
    runtimeInputs = [
      pkgs.jq
      pkgs.systemd
      pkgs.tailscale
    ];
    text = ''
      authority=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')
      main_pid=$(systemctl --user show -p MainPID --value dsh-web.service)
      if [ -z "$main_pid" ] || [ "$main_pid" = "0" ]; then
        echo "dsh-web.service is not running" >&2
        exit 1
      fi
      invocation_id=$(systemctl --user show -p InvocationID --value dsh-web.service)
      if [ -z "$invocation_id" ]; then
        echo "dsh-web.service has not announced its URL yet" >&2
        exit 1
      fi

      token=""
      while IFS= read -r line; do
        case "$line" in
          "dsh web: http://127.0.0.1:${toString dshWebBackendPort}/?token="*)
            token=''${line#*token=}
            break
            ;;
        esac
      done < <(journalctl --user -u dsh-web.service "_SYSTEMD_INVOCATION_ID=$invocation_id" -b --no-pager -o cat)

      if [ -z "$token" ]; then
        echo "dsh-web.service has not announced its URL yet" >&2
        exit 1
      fi

      printf 'https://%s:${toString dshWebProxyPort}/?token=%s\n' "$authority" "$token"
    '';
  };

  piSettings = {
    defaultProvider = "qwen-token-plan-individual";
    defaultModel = "qwen3.8-flash";
    enableInstallTelemetry = false;
    # Adjust per session with the thinking-level picker when a task wants
    # more or less.
    defaultThinkingLevel = "medium";
    # qwen3.8-flash's thinking map only supports high/max (medium is null),
    # so pin a valid level for it rather than letting startup clamp one.
    modelThinkingLevels."qwen-token-plan-individual/qwen3.8-flash" = "high";
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
  # the wrapper above exports from the same secret as QWEN_API_KEY). The
  # custom entries below upsert by id because pi ships a fixed list:
  #   - qwen3.8-flash is served by the subscription but missing from the
  #     individual catalog, so it is added with the metadata pi's broader
  #     qwen-token-plan catalog carries for it.
  #   - deepseek-v4.1-flash (QwenCloud release 2026-09-13) postdates the
  #     bundled catalog, so it is declared here rather than waiting for a
  #     pi-ai bump.
  #   - deepseek-v4-pro-0813 is in the catalog but not the subscription;
  #     models.json cannot remove built-in models, so it stays listed and
  #     simply errors if selected.
  piModels = {
    # Local Ollama. apiKey is the documented placeholder — Ollama ignores it,
    # but pi keeps the model listed (auth-required) until a dummy value is set.
    # _launch is not a pi models.json field (docs/models.md); kept as-is in case
    # another host consumes this entry.
    providers = {
      ollama = {
        api = "openai-completions";
        apiKey = "ollama";
        baseUrl = "http://127.0.0.1:11434/v1";
        models = [
          {
            _launch = true;
            contextWindow = 153600; # ~150k; qwen3.8:160k's max context is 160k, leave headroom
            id = "qwen3.8:160k";
            input = [
              "text"
              "image"
            ];
            reasoning = true;
          }
          {
            _launch = true;
            contextWindow = 153600; # same 160k tag, same headroom
            id = "orcarouter/Qwen3.8-27B-Uncensored:160k";
            input = [
              "text"
              "image"
            ];
            name = "Qwen3.8 27B Uncensored (160k)";
            reasoning = true;
          }
          {
            _launch = true;
            contextWindow = 251904; # 262k tag less 10k, same headroom rule as :160k
            id = "qwen3.8-cyber-iq4xs:262k";
            input = [
              "text"
              "image"
            ];
            name = "Qwen3.8 27B Cyber IQ4_XS (262k)";
            reasoning = true;
            # This tag's chat template takes low/medium/xhigh only (xhigh is
            # its default) and 500s on off/minimal/high, unlike the base
            # qwen3.8 tags' off/high/max, so clamp pi's top levels onto xhigh.
            thinkingLevelMap = {
              off = null;
              minimal = null;
              low = "low";
              medium = "medium";
              high = "xhigh";
              xhigh = "xhigh";
              max = "xhigh";
            };
          }
        ];
      };
      # CrofAI (OpenAI-compatible gateway). Like Ollama this is a provider pi
      # does not ship, so endpoint, protocol, and the full catalog live here.
      crofai = {
        api = "openai-completions";
        apiKey = "$CROFAI_API_KEY";
        baseUrl = "https://crof.ai/v1";
        compat = {
          supportsDeveloperRole = false;
          supportsReasoningEffort = true;
          supportsStore = false;
          maxTokensField = "max_tokens";
        };
        models = crofPiModels;
      };

      openrouter.models = [
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
        # OpenRouter's copy of Union Alpha. It is free and multimodal, but its
        # supported-parameters list has no reasoning field, so no thinking
        # capability is declared; the compat block mirrors the built-in
        # OpenRouter entries so the system prompt travels as `system`.
        {
          id = unionAlpha.openrouterId;
          name = "Union Alpha";
          api = "openai-completions";
          input = [
            "text"
            "image"
          ];
          inherit (unionAlpha) contextWindow maxTokens;
          compat = {
            supportsDeveloperRole = false;
            thinkingFormat = "openrouter";
          };
        }
      ];

      # pi-ai 0.85.1's bundled opencode-go catalog predates Union Alpha, so the
      # free model is upserted by id. `api` also selects the catalog's
      # anthropic-messages baseUrl (https://opencode.ai/zen/go) as the inherited
      # endpoint. The Zen copy is deliberately absent: its free tier only
      # answers requests carrying the OpenCode client's session, which pi does
      # not send.
      "opencode-go".models = [
        {
          id = unionAlpha.opencodeId;
          name = "Union Alpha Free";
          api = "anthropic-messages";
          reasoning = true;
          input = [
            "text"
            "image"
          ];
          inherit (unionAlpha) contextWindow maxTokens;
        }
      ];
      "qwen-token-plan-individual".models = [
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
        {
          id = "deepseek-v4.1-flash";
          name = "DeepSeek V4.1 Flash";
          api = "openai-completions";
          reasoning = true;
          input = [
            "text"
            "image"
          ];
          contextWindow = 1000000;
          maxTokens = 384000;
          compat = {
            thinkingFormat = "qwen";
            supportsDeveloperRole = false;
            supportsStore = false;
            supportsReasoningEffort = true;
          };
          thinkingLevelMap = {
            off = null;
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
  };

  # zvec-grep's MCP server, declared once and then emitted in each host's own
  # shape. opencode's `mcp.<name>` takes the whole argv in `command`; the
  # standard MCP file that pi-mcp-adapter reads (`~/.config/mcp/mcp.json`, the
  # user-global layer of the `mcpServers` format) keeps `command` and `args`
  # apart, and has no `enabled` field at all -- a server is present unless it
  # carries `"disabled": true`. Both use the same server name so the tools the
  #  `zgGuidance` below tells the agent to reach for --
  # `zvec_grep_zvec_grep_search`, `zvec_grep_zvec_grep_rg` -- are the names
  # actually registered: opencode prefixes with the entry name, and the
  # adapter's default `toolPrefix` ("server") does the same.
  zgServerName = "zvec_grep";
  zgArgv = [
    "zg"
    "server"
    "--stdio"
  ];
  # The installer's --mcp-tool-timeout default: 600s in ms.
  #
  # This must stay a plain integer. opencode's user-facing `mcp.<name>` entry is
  # the legacy McpLocalConfig shape, whose `timeout` is a PositiveInt ("Timeout
  # in ms for MCP server requests"). The `{ startup; catalog; execution; }`
  # object belongs to opencode's internal Mcp.TimeoutConfig and is not accepted
  # here: config normalization rejects the whole entry ("skipped malformed
  # recognized value") and the server silently never loads. Verified against
  # opencode2 beta-19378 and opencode 1.18.29.
  zgTimeoutMs = 600000;

  # Microsoft's Playwright MCP server, declared once and rendered in each
  # host's shape next to zvec-grep/ripwire/memory. The nixpkgs package's
  # wrapper already points Playwright at the matching
  # `playwright-driver.browsers` bundle, defaults to Chromium, and turns on
  # `--isolated` unless PLAYWRIGHT_MCP_USER_DATA_DIR is set, so a session
  # starts from an empty in-memory profile and cannot touch the user's real
  # browser profile. `--headless` keeps the same entry usable from a terminal,
  # a desktop launch, and the dsh-web systemd service (no DISPLAY).
  #
  # The argv names the store path rather than relying on PATH: the config is
  # also read by desktop launches and a systemd user service, neither of which
  # is guaranteed to inherit the interactive shell's PATH. Playwright's own
  # default file-access guardrail restricts file access to the server's
  # working directory and blocks file:// navigation; that is a convenience
  # guardrail, not a sandbox boundary.
  pwServerName = "playwright";
  pwArgv = [
    (lib.getExe pkgs.playwright-mcp)
    "--headless"
  ];
  # Browser navigation and first paint can outrun the 60s MCP default.
  pwTimeoutMs = 120000;

  # Shared agent memory: the official knowledge-graph MCP server
  # (`mcp-server-memory`) run once behind mcp-proxy as a systemd *user*
  # service, so every harness reads and writes ONE JSONL graph instead of
  # spawning its own copy. The reference server rewrites the whole file per
  # write and takes no cross-process lock, so a single shared writer is the
  # point -- do not register it per-session over stdio. The store lives on a
  # preserved path (modules/system/preservation.nix); the port is loopback only.
  #
  # opencode names the tools `<server>_<tool>` and pi's adapter does the same
  # with its default `toolPrefix` ("server"); dsh builds `mcp__<server>__<tool>`.
  memoryServerName = "memory";
  memoryPort = 7979;
  memoryUrl = "http://127.0.0.1:${toString memoryPort}/mcp";
  # ExecStart expands %h (the requester's home) to the real path below; the
  # `-e` passthrough is what tells the child stdio server where its graph lives.
  memoryFileSpec = "%h/.local/share/agent-memory/memory.jsonl";

  # The guidance block `zg install` writes, copied verbatim from its 0.2.2
  # opencode output and shared by both hosts: the tool names it cites are the
  # same in each, since opencode prefixes them with the entry name and the
  # adapter's default `toolPrefix` ("server") builds the identical string.
  # Re-derive it from the new package when bumping zvec-grep (run the installer
  # with HOME pointed at a scratch dir). The ZVEC_GREP_START/END markers stay
  # per-host, so `zg install`'s own uninstall can still find its block in
  # opencode's file and pi's extra header below can be dropped wholesale.
  zgGuidance = ''
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
  '';

  # The dsh OpenSandbox tier deliberately does not mount the zvec-grep MCP
  # server: it runs as the host user and accepts arbitrary absolute roots. The
  # sandbox's native Grep/`rg` paths stay inside the mount table, so dsh gets
  # its own short routing note rather than the mcp-name-rendered block above.

  # ripwire's use-when blurb, copied verbatim from the packaged binary's own
  # `ripwire wrap opencode` output (v0.3.8): the CLI-first protocol both
  # harnesses share, since both have a shell tool. Re-derive it the same way
  # (`ripwire wrap opencode`) when bumping ripwire. The RIPWIRE_START/END
  # markers stay per-host, mirroring the ZVEC_GREP block.
  ripwireGuidance = ''
    ## ripwire — deterministic codebase maps (on PATH as `ripwire`)
    Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.
    - Orient on a task: `ripwire <dir> --for="<task in words>"` — ranked, quality-annotated
      signatures. Paste symbol/file names from the issue verbatim; named mentions get anchored.
    - Everything at once under one token budget: `ripwire <dir> --pack-task="<task>"`.
    - Have a stack trace / build error: `ripwire <dir> --from-trace=FILE` (`-` = stdin) —
      paste the error, don't paraphrase it into a query.
    - Who calls X: `--callers=SYM`. "Is it safe to change X?" needs the full blast radius:
      `--impact=SYM` (transitive) plus `--uses=SYM` (every read/write/import site).
    - Just edited a symbol: `--edit-check=SYM` — contract change + newly incompatible callers.
    - Before writing a new fn/class/helper: `--exemplar="<what you're writing>"` — duplicates
      are born on tasks that feel too small to tool up for.
    - Before calling work done: `--quality-delta` (what you made worse), then `--test-gate`.
    - Trust notes: counts marked counts_floor are floors, not totals; a zero means "none
      found", never "none exists".
    Defaults to break (less context is measurably MORE accurate, not just cheaper — code-repair
    accuracy fell 29% -> 3% as context grew 32K -> 256K tokens, LongCodeBench):
    - Do NOT open a file you have not located first: rank with `--for`/`--grep`, then read what it names.
    - Do NOT read a whole file to understand one symbol: `--expand=SYM` gives the body + callee sigs.
    - Do NOT fan reads across several files to learn one thing: `--pack-task="<task>"` is one call.
  '';

  # The upstream package embeds a thin discovery stub at
  # `$out/skills/agent-browser/SKILL.md`; each harness's skill loader only needs
  # a copy under its own root. The one line that does not hold on NixOS is the
  # install command -- there is nothing to install: the CLI is already on PATH
  # via home.packages and Chrome/Chromium comes from home/programs.nix.
  # Replacing that line keeps the package's own name, description, and trigger
  # list version-matched, instead of carrying a parallel hand-written stub that
  # would drift when agent-browser is bumped.
  agentBrowserSkill =
    builtins.replaceStrings
      [ "Install: `npm i -g agent-browser && agent-browser install`" ]
      [
        "Installed by this flake: `agent-browser` is on PATH and Chrome/Chromium is already in the profile. Do not run `npm install -g`, `agent-browser install`, or any nix profile installer; run `agent-browser doctor --json` and report the output if the browser looks missing."
      ]
      (builtins.readFile "${pkgs.agent-browser}/skills/agent-browser/SKILL.md");

  # Cloudflare's security-audit skill (MIT) is a directory bundle: SKILL.md
  # plus domain companions, the report schema, and zero-dependency node
  # validators. It cannot be reproduced from a Nix string the way the
  # agent-browser stub above is, and `npx skills add` would put an unpinned
  # copy outside the flake that the next install silently replaces. Pin the
  # upstream commit instead and bump rev and hash together:
  #
  #   nix-prefetch-url --unpack --type sha256 \
  #     https://github.com/cloudflare/security-audit-skill/archive/<rev>.tar.gz
  #   nix-hash --to-sri --type sha256 <hash>
  #
  # The body only loads on a matching request -- an explicit audit or pen
  # test runs the six-phase workflow, a security question stays
  # guidance-only -- so the catalog entry adds description text, not the
  # ~5k-line bundle, to every session.
  securityAuditSrc = pkgs.fetchFromGitHub {
    owner = "cloudflare";
    repo = "security-audit-skill";
    rev = "c1c8a8c1471069fb0e188eeaff69b8e8db6564a8";
    hash = "sha256-oVVACjotkHvllQGxEP8yWaEt4c3GxT0d909TUM5P3NM=";
  };

  # Copy the bundle out of the fetched tree instead of linking
  # ${securityAuditSrc}/skills/security-audit directly: upstream's MIT
  # LICENSE sits at the repo root, outside the skill directory, and the
  # installed copy should carry the notice with it.
  securityAuditSkill = pkgs.runCommand "security-audit-skill" { } ''
    mkdir -p $out
    cp -r --no-preserve=mode ${securityAuditSrc}/skills/security-audit/. $out/
    cp ${securityAuditSrc}/LICENSE $out/LICENSE
  '';

  # Always-loaded companion to that stub. The skill body is only fetched when
  # the agent loads the skill, so the no-install rule and the snapshot-refresh
  # loop belong in every harness's global instruction file too. The text is the
  # same for dsh, opencode, and pi: agent-browser is a CLI and all three have a
  # shell tool, so there is no harness-specific naming or proxy layer to explain.
  agentBrowserGuidance = ''
    ## Browser automation (agent-browser)

    `agent-browser` is on PATH from this flake and Chrome is already installed;
    do NOT run `npm install -g`, `agent-browser install`, or any nix profile
    installer. The `agent-browser` skill is a discovery stub: before the first
    browser command, load `agent-browser skills get core --full` for the
    version-matched workflow, command reference, and troubleshooting.
    `agent-browser skills list` shows the specialized skills (electron, slack,
    dogfood, webmcp-gen, ...).

    Core loop:
    1. `agent-browser open <url>` — launch and navigate; the daemon keeps the
       session (tabs, cookies, login state) alive between calls.
    2. `agent-browser snapshot -i` — accessibility tree with cheap `@eN` refs.
    3. `agent-browser click @e1` / `fill @e2 "text"` / `get text @e1` /
       `screenshot /abs/path.png`.
    4. Re-run `snapshot -i` after every page change; refs are not stable across
       navigations or DOM updates.

    `agent-browser read <url>` fetches agent-readable text without launching
    Chrome, so prefer it for static/docs pages; reach for the full browser when
    the task needs interaction, login state, or screenshots. Add `--json` when
    parsing output, chain commands with `&&` in one shell call, and run
    `agent-browser close` (or `close --all`) when finished so the daemon does
    not linger. If something looks broken, `agent-browser doctor --json`
    reports Chrome, daemon, and config state; report its output instead of
    installing anything.

    The host also registers Microsoft's Playwright MCP server (isolated,
    headless Chromium; its default file guardrail is scoped to the session
    workspace). Its tools appear directly in opencode and dsh; pi reaches them
    through the `mcp` proxy, so discover them with
    `mcp({ search: "playwright" })`. Prefer it for multi-step interaction when
    an MCP tool is simpler than the shell loop above; the empty in-memory
    profile means it cannot reuse the CLI session's logins.
  '';

  # Shared guidance for the agent-memory server, rendered with the tool names
  # each host actually registers. dsh's `mcp__<server>__<tool>` names are one
  # substitution away.
  memoryGuidance = ''
    ## Agent memory (shared knowledge graph)

    A `memory` MCP server holds a persistent entity/relation/observation
    knowledge graph shared by every harness on this machine. Use it for durable
    facts the user asks you to keep, and to recall earlier decisions,
    preferences and project conventions.

    Tools (names as this host registers them):
    - `${memoryServerName}_search_nodes { query }` — find entities by name, type, or observation text.
    - `${memoryServerName}_open_nodes { names }` — open named entities with their relations.
    - `${memoryServerName}_read_graph` — the whole graph; use sparingly, it can be large.
    - `${memoryServerName}_create_entities { entities: [{ name, entityType, observations }] }`
    - `${memoryServerName}_create_relations { relations: [{ from, to, relationType }] }`
    - `${memoryServerName}_add_observations { observations: [{ entityName, contents }] }`
    - `${memoryServerName}_delete_entities` / `${memoryServerName}_delete_relations` / `${memoryServerName}_delete_observations`

    Rules: store only durable, user-relevant facts — decisions, preferences,
    conventions — not transient chatter. Search before writing, and prefer
    `add_observations` on an existing entity over a near-duplicate one.
    `search_nodes` is substring matching, not semantic, so try distinctive
    terms and synonyms.
  '';
  memoryGuidanceDsh =
    builtins.replaceStrings
      [
        "${memoryServerName}_search_nodes"
        "${memoryServerName}_open_nodes"
        "${memoryServerName}_read_graph"
        "${memoryServerName}_create_entities"
        "${memoryServerName}_create_relations"
        "${memoryServerName}_add_observations"
        "${memoryServerName}_delete_entities"
        "${memoryServerName}_delete_relations"
        "${memoryServerName}_delete_observations"
      ]
      [
        "mcp__${memoryServerName}__search_nodes"
        "mcp__${memoryServerName}__open_nodes"
        "mcp__${memoryServerName}__read_graph"
        "mcp__${memoryServerName}__create_entities"
        "mcp__${memoryServerName}__create_relations"
        "mcp__${memoryServerName}__add_observations"
        "mcp__${memoryServerName}__delete_entities"
        "mcp__${memoryServerName}__delete_relations"
        "mcp__${memoryServerName}__delete_observations"
      ]
      memoryGuidance;

  # Shared by all three harnesses. dsh's own container world and the
  # host-side `osb-work` tool are different execution worlds; this guidance
  # states the default boundary and the two explicit human escape hatches.
  opensandboxGuidance = ''
    ## OpenSandbox work sandboxes

    `osb-work` is the explicit per-work-type sandbox front end on every host
    with the local server (desktop and laptop), and the only path on hosts
    without one. It is a host-side command: the local OpenSandbox API is
    loopback-only and its key lives in the host runtime dir, so it belongs to
    host harnesses and a host terminal, not to a dsh session's own shell.

    In dsh sessions, the @codebam/dsh-opensandbox world runs bash, terminal,
    fs-search, and the file tools inside an OpenSandbox container with the
    session's workspace project mounted at the same absolute path. The default
    mount table is that workspace plus `/nix/store` read-only: no host daemon
    socket, no credential mount, no forwarded
    `GH_TOKEN`/`SSH_AUTH_SOCK`, and no arbitrary host read. Web sessions may
    open any project under the configured workspace parents; a directory
    outside them fails until a human adds it. A human can scope one extra host
    directory with
    `/directory-add <absolute-path> [ro|rw]` (read-only by default); the
    mount lasts for that dsh process. Reviewed host work that genuinely needs
    builds or credentials is a separate human-launched session:
    `dsh-host-access`. Never ask a user to run either command for a path or
    credential you were not explicitly asked to use.

    dsh never falls back by itself if the local server is unhealthy. For one
    session on the built-in bwrap/Landlock world, run `dsh-no-opensandbox`
    (it exports `DSH_NO_OPENSANDBOX=1`); that fallback is not the hardened
    OpenSandbox boundary.

    `osb-work list` enumerates the pinned images (nix, python, web, bun, rust,
    c-cpp, dotnet, lua, steel, shell, browser, code). Start a sandbox with the
    current project bind-mounted at `/workspace`:

    - `osb-work start <type>` — create it and remember the sandbox id;
    - `osb-work exec <type> -- <cmd...>` — run a command in it from `/workspace`;
    - `osb-work stop <type>` — delete it;
    - `osb-work run <type> -- <cmd...>` — one-shot create/run/delete.

    Use `osb` directly for lifecycle flags the helper does not cover. Prefer
    an `osb-work` sandbox over the host shell for untrusted dependencies,
    generated code, package installs, or anything that would touch files
    outside the project; the host `$HOME` and the rest of the user session
    are outside it.
  '';

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

  # The user-settings routes for dsh's llm-pi-ai adapter. pi-ai ships the
  # `opencode-go`, `qwen-token-plan-individual`, and `openrouter` provider
  # catalogs (endpoint, wire protocol, and model list all come from them), so
  # those routes only carry the display label and credential reference; the
  # secrets stay in /run/secrets and `loadKey` above exports them. Keeping this
  # a separate store file means the merge below can deep-merge one namespace
  # without restating the rest of the document.
  dshSettings = pkgs.writeText "dsh-settings-managed.yaml" ''
    llm-pi-ai:
      providers:
        opencode-go:
          displayName: OpenCode Go
          apiKeyEnv: OPENCODE_API_KEY
        # Local Ollama. pi-ai ships no catalog for it, so this route is the
        # whole declaration: protocol, endpoint, and model list. There is no
        # apiKeyEnv on purpose -- Ollama ignores auth, and the Authorization
        # header is the documented placeholder that keeps pi-ai's
        # OpenAI-compatible client from refusing a keyless local route (the
        # credential store stays out of it, and Models-page discovery sends the
        # same header). Metadata mirrors pi's ~/.pi/agent/models.json entries:
        # each tag's max less 10k headroom (160k -> 153600, 262k -> 251904),
        # pi's 16K default output cap, and vision input. Thinking levels follow
        # each tag's own chat template: the base qwen3.8 tags expose off/high/
        # max (`off: none` is how Ollama spells "no thinking" there -- omitting
        # the field means think), while the cyber tag exposes low/medium/xhigh.
        ollama:
          displayName: Ollama
          api: openai-completions
          baseURL: http://127.0.0.1:11434/v1
          headers:
            Authorization: Bearer ollama
          reasoning: high
          models:
            - id: qwen3.8:160k
              name: Qwen3.8 27B (160k)
              contextWindow: 153600
              maxTokens: 16384
              input:
                - text
                - image
              reasoningEfforts:
                off: none
                high: high
                max: max
            - id: orcarouter/Qwen3.8-27B-Uncensored:160k
              name: Qwen3.8 27B Uncensored (160k)
              contextWindow: 153600
              maxTokens: 16384
              input:
                - text
                - image
              reasoningEfforts:
                off: none
                high: high
                max: max
            - id: qwen3.8-cyber-iq4xs:262k
              name: Qwen3.8 27B Cyber IQ4_XS (262k)
              contextWindow: 251904
              maxTokens: 16384
              input:
                - text
                - image
              # This tag's template takes low/medium/xhigh only (xhigh is its
              # default) and 500s on the base tags' off/high/max, so declare
              # the three it accepts rather than reusing their map.
              reasoningEfforts:
                low: low
                medium: medium
                xhigh: xhigh
        # DeepSeek V4.1 Flash (OpenCode model id `deepseek-flash`) is served by
        # OpenCode Go but is not in pi-ai's bundled `opencode-go` catalog
        # (0.84.4), and a hand-declared model cannot be appended to that route:
        # its models speak three wire protocols, so `models` would have to
        # replace the whole catalog and a route-level `api` would mislabel the
        # anthropic/responses entries. A dedicated single-model route keeps the
        # catalog route intact; the session-header plugin is told about its key
        # in the profile patch. models.dev carries no `deepseek-flash` entry,
        # only the text-only deepseek-v4-flash and the vision
        # deepseek-v4.1-flash / deepseek-v4-flash-vision-exp pair, so an
        # undeclared route would default to text-only and refuse image
        # attachments. The endpoint accepts images for this id, so `input`
        # declares both modalities; the rest mirrors the deepseek-v4-flash
        # sibling (context 1M, output 384k) with dsh's own
        # reasoningEfforts/compat shape.
        opencode-go-deepseek:
          displayName: OpenCode Go (DeepSeek)
          apiKeyEnv: OPENCODE_API_KEY
          api: openai-completions
          baseURL: https://opencode.ai/zen/go/v1
          models:
            - id: deepseek-flash
              name: DeepSeek V4.1 Flash
              contextWindow: 1000000
              maxTokens: 384000
              input:
                - text
                - image
              reasoningEfforts:
                low: low
                high: high
                max: max
              compat:
                supportsStore: false
                supportsDeveloperRole: false
                maxTokensField: max_tokens
                requiresReasoningContentOnAssistantMessages: true
                thinkingFormat: deepseek

        # Union Alpha Free is served by OpenCode Go but missing from pi-ai
        # 0.85.1's bundled catalog. The opencode-go route's catalog speaks
        # three wire protocols, so appending this anthropic-messages model
        # through a `models` list would replace the whole catalog; the
        # dedicated route is the same workaround opencode-go-deepseek uses.
        # pi-ai's anthropic-messages client appends /v1/messages to the
        # built-in catalog's baseURL. The route name must be listed in the
        # opencode-go-session-header plugin below, or OpenCode Go answers 400
        # MissingSessionID. models.dev reports reasoning with no advertised
        # effort options, so the offered levels mirror pi-ai's default for the
        # Go catalog's other anthropic models; off stays valueless because not
        # thinking is the absence of the thinking parameter, and minimal maps
        # onto low so an adaptive-thinking endpoint never sees an invalid
        # effort spelling.
        opencode-go-union-alpha:
          displayName: OpenCode Go (Union Alpha)
          apiKeyEnv: OPENCODE_API_KEY
          api: anthropic-messages
          baseURL: https://opencode.ai/zen/go
          models:
            - id: union-alpha
              name: Union Alpha Free
              contextWindow: 262144
              maxTokens: 131072
              input:
                - text
                - image
              reasoningEfforts:
                off:
                minimal: low
                low: low
                medium: medium
                high: high

        # Qwen Cloud Token Plan. The endpoint, wire protocol, and
        # Personal-Edition catalog come from pi-ai's
        # qwen-token-plan-individual provider, keyed from
        # QWEN_TOKEN_PLAN_API_KEY (which `loadKey` exports from the same
        # secret as QWEN_API_KEY, the name pi-ai's ambient discovery looks
        # for).
        #
        # pi-ai 0.85.1's bundled catalog predates deepseek-v4.1-flash
        # (QwenCloud release 2026-09-13), and llm-pi-ai has no upsert: a
        # `models` list replaces the route's catalog, so the installed ids
        # are restated bare (each defaults from its catalog entry) and only
        # the new model carries its own metadata.
        qwen-token-plan-individual:
          displayName: Qwen Cloud (Token Plan)
          apiKeyEnv: QWEN_TOKEN_PLAN_API_KEY
          models:
            - id: qwen3.8-max
            - id: qwen3.8-flash
            - id: qwen3.7-max
            - id: qwen3.7-plus
            - id: qwen3.6-flash
            - id: glm-5.2
            - id: deepseek-v4-pro
            - id: deepseek-v4-pro-0813
            - id: deepseek-v4-flash-0731
            - id: deepseek-v4.1-flash
              name: DeepSeek V4.1 Flash
              contextWindow: 1000000
              maxTokens: 384000
              input:
                - text
                - image
              # Omit off: dsh's reasoningEfforts key means selectable;
              # absent resolves to thinkingLevelMap.off = null (unsupported),
              # matching pi-ai's deepseek catalog, while an explicit empty
              # off: would declare off selectable and send nothing.
              reasoningEfforts:
                high: high
                max: max
              compat:
                thinkingFormat: qwen
                supportsDeveloperRole: false
                supportsStore: false
                supportsReasoningEffort: true

        # OpenRouter's full installed catalog (351 openai-completions plus 15
        # anthropic-messages models at pi-ai 0.85.1), keyed from
        # OPENROUTER_API_KEY, which `loadKey` exports from the
        # `openrouter-api-key` sops secret.
        #
        # `openrouter/pareto-code` is deliberately not declared even though
        # opencode and pi both select it: the Pareto router's price/capability
        # floor travels in a request-body `plugins` entry, and dsh's pi-ai
        # profile exposes no field that reaches the request body (only
        # headers, compat switches, and the like). Without that plugin the
        # router picks the strongest available coder -- the expensive end --
        # so leaving it out is the safe default; the catalog's
        # `openrouter/auto` remains available as an ordinary router.
        openrouter:
          displayName: OpenRouter
          apiKeyEnv: OPENROUTER_API_KEY

        # Union Alpha on OpenRouter. pi-ai 0.85.1's installed catalog predates
        # it, and neither way of extending that route works: a `models` list
        # would replace all 366 catalog entries, and `modelOverrides` refuses
        # an id the catalog does not describe. The dedicated route is the same
        # workaround as above. pi-ai detects openrouter.ai from the baseURL, so
        # the wire compatibility (developer role, thinking format, usage
        # streaming) needs no compat block. OpenRouter's copy advertises no
        # reasoning parameter, unlike the OpenCode Go route, so it is declared
        # non-reasoning.
        openrouter-union-alpha:
          displayName: OpenRouter (Union Alpha)
          apiKeyEnv: OPENROUTER_API_KEY
          api: openai-completions
          baseURL: https://openrouter.ai/api/v1
          models:
            - id: stealth/union-alpha
              name: Union Alpha
              contextWindow: 262144
              maxTokens: 131072
              input:
                - text
                - image
              reasoningEfforts: false

        # CrofAI (OpenAI-compatible gateway). Not a pi-ai catalog route, so
        # this profile is the whole declaration: endpoint, protocol, and the
        # same catalog the other two harnesses carry. The compat block mirrors
        # pi's models.json: the baseURL says nothing, so without it pi-ai
        # defaults to the `developer` role and `store`, which CrofAI refuses.
        crofai:
          displayName: CrofAI
          apiKeyEnv: CROFAI_API_KEY
          api: openai-completions
          baseURL: https://crof.ai/v1
          compat:
            supportsStore: false
            supportsDeveloperRole: false
            supportsReasoningEffort: true
            maxTokensField: max_tokens
    ${crofDshModelsYaml}
  '';

  # Hermes' token-plan providers. The upstream module ships built-in catalogs
  # for OpenCode Go and DeepSeek, which the extended hermes-env template in
  # desktop/configuration/sops.nix unlocks with OPENCODE_GO_API_KEY /
  # DEEPSEEK_API_KEY; home/hermes.nix keeps OpenRouter pinned as the startup
  # default. The two plans below have no Hermes catalog or point at the wrong
  # endpoint out of the box:
  #
  #   - Qwen Cloud's Token Plan speaks Anthropic Messages (the vendor's
  #     opencode recipe), while Hermes' built-in `alibaba` provider speaks
  #     OpenAI-compatible DashScope; declare the vendor endpoint directly.
  #   - CrofAI is an OpenAI-compatible gateway absent from models.dev, with
  #     its catalog already carried in crofModels above.
  #
  # Model metadata is projected from the same qwenProvider/crofModels shapes
  # the other harnesses use, so the plan lists cannot drift between agents.
  hermesProviderModels = {
    qwen-token-plan = lib.mapAttrs (_: model: {
      context_length = model.limit.context;
      supports_reasoning = model.reasoning or false;
      supports_tools = model.tool_call or false;
      supports_vision = builtins.elem "image" (model.modalities.input or [ ]);
    }) qwenProvider.qwen.models;

    crofai = builtins.listToAttrs (
      map (model: {
        name = model.id;
        value = {
          context_length = model.context;
          supports_reasoning = model.reasoning;
          supports_vision = model.vision;
        };
      }) crofModels
    );
  };

  hermesProviders = {
    qwen-token-plan = {
      name = "Qwen Cloud (Token Plan)";
      api = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic/v1";
      key_env = "QWEN_TOKEN_PLAN_API_KEY";
      transport = "anthropic_messages";
      # This gateway has no Anthropic /v1/models surface, so the picker uses
      # the declared list instead of probing it.
      discover_models = false;
      models = hermesProviderModels.qwen-token-plan;
    };

    crofai = {
      name = "CrofAI";
      api = "https://crof.ai/v1";
      key_env = "CROFAI_API_KEY";
      transport = "chat_completions";
      # Same reason as Qwen: crofModels is the maintained catalog.
      discover_models = false;
      models = hermesProviderModels.crofai;
    };
  };

  # settings.yaml is dsh's live user-overrides document: the Models page and the
  # onboarding/permission toggles write it, and dsh hot-reloads external edits.
  # So it cannot be a read-only store symlink any more than pi's settings.json
  # can; merge the managed namespace into it instead, preserving every key dsh
  # wrote. An unparseable document (a half-finished hand edit) is backed up
  # rather than silently overwritten, then rebuilt from the managed keys.
  dshSettingsMerge = pkgs.writeShellScript "dsh-settings-merge" ''
    set -eu
    settings="$HOME/.dsh/settings.yaml"
    mkdir -p "$HOME/.dsh"
    if [ -s "$settings" ] && ! ${pkgs.yq-go}/bin/yq -e '.' "$settings" >/dev/null 2>&1; then
      cp "$settings" "$settings.invalid"
      printf '{}\n' > "$settings"
    fi
    if [ ! -s "$settings" ]; then
      printf '{}\n' > "$settings"
    fi
    ${pkgs.yq-go}/bin/yq -i ". * load(\"${dshSettings}\")" "$settings"
  '';
in
{
  home = {
    packages = [
      opencode
      opencode-desktop
      opencode-desktop-beta
      opencode2
      pi
      dshInstalled
    ]
    ++ lib.optionals isDesktop [
      dshWebUrl
    ]
    ++ lib.optionals (podmanEnabled && dshContainerWorld) [
      dshNoOpenSandbox
      dshHostAccess
    ];

    # Nested rather than three top-level `activation.` keys: statix's
    # repeated-keys lint flags the flat form once the third entry lands.
    activation = {
      # Pi's settings.json is mutable state — `/settings` and the model picker
      # write to it — so it cannot be a read-only store symlink like opencode's
      # config. Merge instead, nix keys winning, the same way the hermes module
      # handled its own config.yaml.
      piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${piSettingsMerge}
      '';

      # dsh's settings.yaml is the same kind of live document (onboarding, chat
      # prefs, permission preset, Models page), so it gets the same merge
      # treatment: Nix owns only the llm-pi-ai OpenCode Go route.
      dshSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${dshSettingsMerge}
      '';

      # One-shot cleanup after dropping the nono provider: the old activation
      # copied this module into $DSH_HOME, which home-manager does not manage
      # and therefore does not remove when the provider goes away.
      dshNonoCleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/rm -f "$HOME/.dsh/profiles/nono/index.mjs"
        run ${pkgs.coreutils}/bin/rmdir "$HOME/.dsh/profiles/nono" 2>/dev/null || true
      '';

      # @codebam/dsh-opensandbox is published from its own repository, pinned
      # in pkgs/dsh-opensandbox.nix so a reaped sandbox is revalidated rather
      # than left with a dead execd endpoint. Copy it into $DSH_HOME rather
      # than symlinking: Node resolves a module through its symlink target, so
      # a symlinked module would look for @deepseek-ai/* next to the store
      # directory instead of the profile's node_modules. Only runs when
      # dshContainerWorld is enabled above.
      dshOpenSandbox = lib.mkIf (podmanEnabled && dshContainerWorld) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.coreutils}/bin/install -d -m 0755 "$HOME/.dsh/profiles/opensandbox"
          run ${pkgs.coreutils}/bin/cp -f ${pkgs.dsh-opensandbox}/lib/dsh-opensandbox/index.mjs "$HOME/.dsh/profiles/opensandbox/index.mjs"
          # cp -r copies the store source directory's 0555 mode onto the
          # destination, so a tree copied by an earlier activation cannot be
          # unlinked by this user on the next one ("rm: ... Permission
          # denied", failing the whole switch). Repair the old tree before
          # replacing it and leave the new one writable.
          run ${pkgs.coreutils}/bin/chmod -R u+w "$HOME/.dsh/profiles/opensandbox/src" 2>/dev/null || true
          run ${pkgs.coreutils}/bin/rm -rf "$HOME/.dsh/profiles/opensandbox/src"
          run ${pkgs.coreutils}/bin/cp -r ${pkgs.dsh-opensandbox}/lib/dsh-opensandbox/src "$HOME/.dsh/profiles/opensandbox/src"
          run ${pkgs.coreutils}/bin/chmod -R u+w "$HOME/.dsh/profiles/opensandbox/src"
          run ${pkgs.coreutils}/bin/cp -f ${pkgs.dsh-opensandbox}/lib/dsh-opensandbox/package.json "$HOME/.dsh/profiles/opensandbox/package.json"
          run ${pkgs.coreutils}/bin/rm -f "$HOME/.dsh/profiles/opensandbox/node_modules"
          run ${pkgs.coreutils}/bin/ln -sfn "$HOME/.dsh/profiles/node_modules" "$HOME/.dsh/profiles/opensandbox/node_modules"
        ''
      );

      # @codebam/dsh-tool-nu is published from its own repository, pinned in
      # pkgs/dsh-tool-nu.nix. Copy it into $DSH_HOME rather than symlinking:
      # Node resolves a module through its symlink target, so a symlinked
      # module would look for @deepseek-ai/* next to the store directory
      # instead of the profile's node_modules. Same podman gate as the
      # dshOpenSandbox block: only hosts whose dsh profiles carry the patch
      # file get the plugin.
      dshToolNu = lib.mkIf (podmanEnabled && dshContainerWorld) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.coreutils}/bin/install -d -m 0755 "$HOME/.dsh/profiles/tool-nu"
          run ${pkgs.coreutils}/bin/cp -f ${pkgs.dsh-tool-nu}/lib/dsh-tool-nu/index.mjs "$HOME/.dsh/profiles/tool-nu/index.mjs"
          # cp -r copies the store source directory's 0555 mode onto the
          # destination, so repair an older copied tree before replacing it
          # (same reason as the dshOpenSandbox block).
          run ${pkgs.coreutils}/bin/chmod -R u+w "$HOME/.dsh/profiles/tool-nu/src" 2>/dev/null || true
          run ${pkgs.coreutils}/bin/rm -rf "$HOME/.dsh/profiles/tool-nu/src"
          run ${pkgs.coreutils}/bin/cp -r ${pkgs.dsh-tool-nu}/lib/dsh-tool-nu/src "$HOME/.dsh/profiles/tool-nu/src"
          run ${pkgs.coreutils}/bin/chmod -R u+w "$HOME/.dsh/profiles/tool-nu/src"
          run ${pkgs.coreutils}/bin/cp -f ${pkgs.dsh-tool-nu}/lib/dsh-tool-nu/package.json "$HOME/.dsh/profiles/tool-nu/package.json"
          run ${pkgs.coreutils}/bin/rm -f "$HOME/.dsh/profiles/tool-nu/node_modules"
          run ${pkgs.coreutils}/bin/ln -sfn "$HOME/.dsh/profiles/node_modules" "$HOME/.dsh/profiles/tool-nu/node_modules"
        ''
      );
    };

    # models.json, unlike settings.json, is user-authored config that pi only
    # reads, so it can be a plain store symlink.
    #
    # Nested rather than repeated top-level `file.` keys: statix's
    # repeated-keys lint flags the flat form once the third entry lands, the
    # same reason the opencode config below sits under one `xdg.configFile`.
    file = {
      ".pi/agent/models.json".text = builtins.toJSON piModels;

      # The same version-matched discovery stub for the two non-opencode roots:
      # pi scans `~/.pi/agent/skills` and dsh scans `~/.dsh/skills`. opencode's
      # copy lives under xdg.configFile below.
      ".pi/agent/skills/agent-browser/SKILL.md".text = agentBrowserSkill;
      ".dsh/skills/agent-browser/SKILL.md".text = agentBrowserSkill;

      # Cloudflare's security-audit bundle in dsh's user skill root
      # (`~/.dsh/skills`, rank 400). The target is a symlink to the bundle;
      # dsh's provider follows symlinked entries when it scans.
      ".dsh/skills/security-audit".source = securityAuditSkill;

      # Files the dsh container world reads through its read-only mounts
      # (see dshProfilePatch below).
      #
      # The git config `include`s the real one -- identity, signing key and
      # credential helpers stay authoritative in one place -- and adds the two
      # programs the read-only mounts cannot run as-is: gpg needs a writable
      # homedir (dshSandboxGpg above), and ssh needs a known_hosts that is not
      # ~/.ssh, which holds an unencrypted private key that a read-only mount
      # would still hand to every sandbox.
      ".config/dsh-sandbox/gitconfig".text = ''
        [include]
        	path = ${config.home.homeDirectory}/.config/git/config
        [gpg]
        	program = ${dshSandboxGpg}/bin/dsh-sandbox-gpg
        [core]
        	sshCommand = ssh -o UserKnownHostsFile=${config.home.homeDirectory}/.config/dsh-sandbox/known_hosts
      '';

      # GitHub's published host keys (https://api.github.com/meta). Public data,
      # kept separate from ~/.ssh for the reason above.
      ".config/dsh-sandbox/known_hosts".text = ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
        github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
        github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
      '';

      # pi's global context file (docs/usage.md: "Context Files"). pi is not one
      # of `zg install`'s targets -- codex, claude, qwen, qoder, opencode and
      # cursor are -- so this is the shared guidance above plus a hand-written
      # header for the one thing that differs: under the adapter the tools are
      # behind the `mcp` proxy and lazy, so they are NOT in pi's tool list when a
      # session starts, and the verbatim "when it is listed by the current host"
      # would otherwise send pi straight to native rg.
      #
      # `directTools = true` on the server entry would register them as ordinary
      # pi tools and make this header unnecessary, at the cost of their schemas
      # sitting in context every session -- the thing the adapter exists to avoid.
      #
      # Like models.json this is a file pi only reads, so a plain store symlink is
      # right. If a hand-written ~/.pi/agent/AGENTS.md ever appears first,
      # activation fails loudly rather than clobbering it: merge it in, or set
      # `force = true`.
      #
      # Caveat: the adapter itself is ambient, not declared here -- it came from
      # `pi install npm:pi-mcp-adapter` into ~/.pi/agent/npm, alongside the other
      # extensions. Point a fresh machine at this config without installing it and
      # pi is handed instructions for a tool it does not have.
      ".pi/agent/AGENTS.md".text = ''
        <!-- ZVEC_GREP_START -->
        ## zvec-grep is an MCP server here, not a tool list

        pi reaches zvec-grep through pi-mcp-adapter's single `mcp` proxy tool, and that server is lazy: none of its tools appear in the tool list at session start.

        - Discover: `mcp({ search: "zvec_grep" })` — "semantic search", "workspace grep" and "code index" find it too.
        - Parameters: `mcp({ describe: "zvec_grep_zvec_grep_search" })`.
        - Call: `mcp({ tool: "zvec_grep_zvec_grep_search", args: { root: "/absolute/path", query: "…" } })`. The prefixed name is the address; `args` is the server's own parameter object (`root` is required, absolute, daemon-visible).
        - Several retrieval round trips in one turn: `mcpScript` with `tools.zvec_grep_zvec_grep_search(args)`.
        - The first call connects and starts the stdio bootstrap, so judge availability after it rather than from the empty initial tool list. Where the rules below say "when it is listed by the current host", read that as "once `mcp({ search })` has returned it".
        - `zvec_grep_rg` — the managed exact/regex route — is only exposed when the server runs with `--mcp-toolset full`. This config keeps the installer default (`agent` toolset, indexed search only), so exact lookups go to native Grep or `rg`, which makes the indexed route the one worth calling at all.

        ${zgGuidance}
        <!-- ZVEC_GREP_END -->
        <!-- RIPWIRE_START -->
        ## ripwire is a CLI first, MCP server second here

        ripwire is on PATH. Prefer the CLI forms in the block below via Bash —
        they cost no context until invoked.

        The MCP server (`ripwire --mcp`, registered in ~/.config/mcp/mcp.json)
        is the warm-index alternative, reached through pi-mcp-adapter's single
        `mcp` proxy tool exactly like zvec-grep above: `mcp({ search: "ripwire" })`
        to discover, then `mcp({ tool: "ripwire_<verb>", args: { path: "/absolute/path", ... } })`
        (verbs include `for`, `explore`, `impact`, `find_symbol`, `quality_delta`).
        The first call connects and starts the stdio bootstrap, so judge
        availability after it rather than from the empty initial tool list.

        ${ripwireGuidance}
        <!-- RIPWIRE_END -->
        <!-- AGENT_BROWSER_START -->
        ${agentBrowserGuidance}
        <!-- AGENT_BROWSER_END -->
        <!-- MEMORY_START -->
        ${memoryGuidance}
        <!-- MEMORY_END -->
        <!-- OPENSANDBOX_START -->
        ${opensandboxGuidance}
        <!-- OPENSANDBOX_END -->
      '';

      # dsh reads exactly one user-global instruction file, `$DSH_HOME/AGENTS.md`,
      # through `@deepseek-ai/dsh-agent-instructions` (plus the per-directory
      # AGENTS.md/CLAUDE.md chain and the AGENTS.local.md/CLAUDE.local.md overlays
      # under the project root). The web profile disables the host row and makes
      # each preset opt in, which minimal-agents does below. It does
      # not look at ~/.claude/CLAUDE.md, ~/.pi/agent/AGENTS.md, or opencode's
      # copy, so the shared tooling rules need a dsh copy; the zvec-grep block is
      # the dsh-named rendering from above, and the MCP servers are ordinary
      # listed tools here rather than something behind a lazy proxy.
      #
      # The tooling rules also live in the hand-written ~/.claude/CLAUDE.md. That
      # file stays hand-written because Claude Code's `/memory` can rewrite it,
      # which a read-only store symlink would break; merge this binding in if it
      # ever stops being edited there.
      ".dsh/AGENTS.md".text = ''
        # Tooling
        * Ephemeral Nix tools: prefer `nix shell nixpkgs#<pkg>… -c <cmd>` or `nix run nixpkgs#<pkg> -- …` when
          the package is known; use `, <cmd>` only as the binary-name fallback. No install requests for
          one-offs; never `nix profile install` / `nix-env -i` — declared tools belong in the flake/module.
        * Find before running: `nix-locate -w -t x 'bin/<cmd>'` (or `, -p <cmd>`) maps a command to its package;
          `nh search packages --json "<term>"` and `nh search options --json "<term>"` query the live
          search.nixos.org index; `, manix --source nixos-options "<term>"` searches offline. Prefer
          `nix eval --json` / `nix repl` over parsing human output.
        * Verify NixOS options, never guess: `nixos-option -F .#<host> [-r] <option.path>` evaluates this
          flake's real option tree; `nix develop` provides `nil`/`nixd` completions.
        * NixOS changes are declarative: `git add` new files first (flakes ignore untracked files); secrets go
          through SOPS, never into the store or git; verify with `nh os build .#<host>` (or
          `nixos-rebuild build --flake .#<host>`), `nix build .#checks.x86_64-linux.lint`, `nix flake check`
          when broad, and `nix fmt`. Build and report; activation is the human's call — never
          `switch`/`boot`/`test`, and no rollback, GC, or imperative profile/channel writes unless the user
          explicitly asks.
        * Build/log forensics: `nh`/`nom` tree output; `nix-tree`, `nix why-depends`, `nix path-info` for
          closures; `nvd diff` for generation changes. Filter logs >50 lines with `awk`/`sed`/`jq`/`rg`
          before reading.

        <!-- ZVEC_GREP_START -->
        ## zvec-grep is not mounted in this dsh tier

        The host-side `zvec_grep` MCP server is deliberately absent from the
        OpenSandbox dsh profile because it reads arbitrary host paths. For
        exact lookups use the native Grep tool or `rg` via bash; those run in
        the sandbox against the mounted workspace. Ask the user before adding
        any host bridge for semantic indexing.

        <!-- ZVEC_GREP_END -->
        <!-- RIPWIRE_START -->
        ## ripwire is a CLI first here

        ripwire is on PATH inside the sandbox and dsh has a shell tool, so use
        the CLI forms below via bash; they cost no context until invoked. The
        host-side `ripwire` MCP server is deliberately not mounted in this
        tier.

        ${ripwireGuidance}
        <!-- RIPWIRE_END -->
        <!-- AGENT_BROWSER_START -->
        ${agentBrowserGuidance}
        <!-- AGENT_BROWSER_END -->
        <!-- MEMORY_START -->
        ${memoryGuidanceDsh}
        <!-- MEMORY_END -->
        <!-- OPENSANDBOX_START -->
        ${opensandboxGuidance}
        <!-- OPENSANDBOX_END -->
      '';

      # dsh's user-global patch layer. Precedence is bundle layers, then the
      # profile's own `cordis.patch.yml`, then this file, then `--patch`
      # overlays, so rows here apply to every profile: web, headless, acp, sdk,
      # and the custom dsh-tui profile.
      #
      # The memory server and the Playwright MCP server are mounted here; the
      # other host-side bridges (zvec-grep, ripwire, opensandbox) are
      # intentionally absent from the default agent tier: they run as the host
      # user and accept arbitrary host paths, arbitrary sandboxes, or
      # arbitrary commands. Their CLIs remain available inside the sandbox
      # (where they run against the mounted workspace), and the per-work-type
      # sandboxes remain available through `osb-work` on the host side.
      #
      # Playwright is the deliberate exception for browser automation: it
      # runs as the host user and therefore on the host network, so it can
      # reach public web and host-loopback URLs the container's own shell
      # cannot. Its file access defaults to the session workspace and is a
      # convenience guardrail, not a security boundary; the isolated, headless
      # profile keeps it out of the user's real browser. Re-review it with the
      # same care as `dsh-host-access` if the threat model changes.
      #
      # The memory URL is served stateless by mcp-proxy (see the agent-memory
      # unit below), so dsh's MCP SDK v2 client talks to it without a session.
      #
      # Written as YAML text (the loader reads YAML, not JSON); the row sits
      # inside a top-level `insert` with no `id`, because a patch entry with
      # an `id` and no `insert` only overrides a row that already exists.
      ".dsh/cordis.patch.yml".text = ''
        - insert:
            - id: mcp-memory
              name: '@deepseek-ai/dsh-mcp-client'
              config:
                serverName: ${memoryServerName}
                transport: streamable-http
                url: ${memoryUrl}

            - id: mcp-playwright
              name: '@deepseek-ai/dsh-mcp-client'
              config:
                serverName: ${pwServerName}
                transport: stdio
                command: ${builtins.toJSON (builtins.head pwArgv)}
                args: ${builtins.toJSON (builtins.tail pwArgv)}
                toolCallTimeoutMs: ${toString pwTimeoutMs}
      '';

      # The Minimal-Agents agent preset, authored in the user preset root
      # `$DSH_HOME/.agent-presets` beside `liangshen` rather than patched into the
      # shipped root from pkgs/dsh.nix. The roster scans the shipped presets
      # first and this root last (`includeUserRoot`), the directory name is the
      # preset id (so it must be lowercase), and `preset.yml` supplies the
      # display name -- the TUI therefore offers it as "Minimal-Agents" in
      # `/preset` and the choice is per session, not a change of the default.
      #
      # Composition: the shipped `minimal` preset's persona and persistent-shell
      # rows verbatim (same one-line prompt, `complete: true` so no other prompt
      # section can add text, no runtime context, bash as the only built-in
      # tool), plus dsh-base's delegation rows and the agent-instructions row that
      # the web profile makes each preset opt into. `tool-workflow` and `tool-ralph`
      # are deliberately absent: this is "minimal + agents", not minimal plus the
      # workflow engine. The subagents registry and the spawn/fork backends stay
      # in the host composition; these rows only contribute the tools that
      # resolve it. See the composition's own header for the rest.
      ".dsh/.agent-presets/minimal-agents/agent.cordis.yml".text = ''
        # The `minimal-agents` agent preset: the shipped `minimal` composition plus
        # workspace instructions, the subagent delegation tools, and local skills.
        #
        # The persona block is `minimal`'s verbatim (fixed prompt, complete: true, no
        # runtime context), so identity/Web/tool-guidance sections still cannot add
        # prompt text here, and the persistent shell is still the only built-in shell.
        # `suffix` states the working directory for the same reason pkgs/dsh.nix adds it
        # to the shipped `minimal`: complete: true suppresses the runtime-context snapshot.
        #
        # The delegation rows mirror the dsh-base bundle's four, minus `tool-workflow`
        # and `tool-ralph`: "agents" means spawning and steering subagents, not the
        # workflow engine. A spawned child inherits this preset by joining the parent's
        # standing composition (AgentPresets.composeFrom), so a delegated agent gets the
        # same shell and this same toolset; `maxDepth` is left at its package default.
        #
        # The `subagents` registry and its spawn/fork backends live in the HOST
        # composition (dsh-base, where the dsh-tui bundle patch leaves them enabled
        # while disabling the host-level tool rows). These rows therefore register the
        # delegation TOOLS only and must NOT be isolated: their `subagents` inject has
        # to resolve that host registry. That is why this group has no `isolate` block,
        # unlike `persistent-shell` below, whose PTY registry is agent-owned.

        - id: persona
          name: '@deepseek-ai/dsh-persona'
          config:
            prefix: You are a helpful software engineer assistant.
            suffix: Your working directory is {{cwd}}.
            complete: true
            includeRuntimeContext: false

        # dsh-web disables dsh-base's host-level agent-instructions row and makes
        # each preset opt in (standard does). minimal does not, so without this row
        # a minimal-agents session never receives `$DSH_HOME/AGENTS.md` or the repo
        # `AGENTS.md` chain -- not as a system prompt and not as a system-reminder.
        # The persona's `complete: true` only suppresses system-prompt sections; this
        # plugin injects workspace context as a separate user-message baseline.
        - id: agent-instructions
          name: '@deepseek-ai/dsh-agent-instructions'
          config:
            maxBytes: 65536

        # The PTY registry is an agent-owned service, so it lives in an entry-local
        # realm. The backend still consumes the host sandbox policy and subprocess
        # implementation, while the tool registers into this agent's scoped catalog.
        # Exactly one shell stack mounts per host: the bash stack gates off win32 and
        # its pwsh twin gates off POSIX, mirroring the one-shot shell rows.
        - id: persistent-shell
          name: cordis:group
          group: true
          isolate:
            terminals: true
          config:
            - id: pty
              name: '@deepseek-ai/dsh-terminal'

            - id: terminal-bash
              name: '@deepseek-ai/dsh-terminal-bash'
              disabled: !!js process.platform === 'win32'
              config:
                timeoutMs: 300000

            - id: persistent-bash
              name: '@deepseek-ai/dsh-tool-bash-persistent'
              disabled: !!js process.platform === 'win32'
              config:
                timeoutMs: 300000
                description: |-
                  Run commands in a bash shell
                  * When invoking this tool, the contents of the "command" parameter does NOT need to be XML-escaped.
                  * Network access depends on the task environment. Prefer configured mirrors/proxies when they are available.
                  * State is persistent across command calls and discussions with the user.
                  * To inspect a particular line range of a file, e.g. lines 10-25, try 'sed -n 10,25p /path/to/the/file'.
                  * Please avoid commands that may produce a very large amount of output.
                  * Please run long lived commands in the background, e.g. 'sleep 10 &' or start a server in the background.

            - id: terminal-pwsh
              name: '@deepseek-ai/dsh-terminal-bash'
              disabled: !!js process.platform !== 'win32'
              config:
                shellDialect: pwsh
                timeoutMs: 300000

            - id: persistent-pwsh
              name: '@deepseek-ai/dsh-tool-pwsh-persistent'
              disabled: !!js process.platform !== 'win32'
              config:
                timeoutMs: 300000
                description: |-
                  Run commands in a PowerShell shell
                  * When invoking this tool, the contents of the "command" parameter does NOT need to be XML-escaped.
                  * You don't have access to the internet via this tool.
                  * State is persistent across command calls and discussions with the user.
                  * Use native Windows paths (C:\...) and $env:NAME variables; this is PowerShell, not bash.
                  * Please avoid commands that may produce a very large amount of output.
                  * Please run long lived commands in the background, e.g. 'Start-Job' or start a server with Start-Process.

        # Compaction: `/compact` and automatic history compaction are
        # agent-plane choices, so a preset that omits this group has neither.
        # The isolate realm keeps this preset's compaction instance private,
        # like persistent-shell above.
        - id: compaction
          name: cordis:group
          group: true
          isolate:
            compaction: true
            toolResultPruner: true
          config:
            - id: compaction-basic
              name: '@deepseek-ai/dsh-compaction-basic'

            - id: command-compact
              name: '@deepseek-ai/dsh-command-compact'

            - id: tool-result-pruner
              name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
              config:
                thresholdChars: 8192
                headChars: 4096
                tailChars: 1024

        # Continuous delegation: the spawn/fork tools plus the control API over
        # continuable children (`send_message`/`interrupt_agent` and `list_agents`).
        - id: delegation
          name: cordis:group
          group: true
          config:
            - id: tool-subagent-control
              name: '@deepseek-ai/dsh-tool-subagent-control'

            - id: tool-subagent-list-agents
              name: '@deepseek-ai/dsh-tool-subagent-control/list-agents'

            - id: tool-subagent
              name: '@deepseek-ai/dsh-tool-subagent'
              config:
                provider: spawn
                toolName: subagent
                backgroundMode: continuable

            - id: tool-subagent-fork
              name: '@deepseek-ai/dsh-tool-subagent'
              config:
                provider: fork
                toolName: subagent_fork
                backgroundMode: one-shot

        # Skills: the Web surface disables the host-level `skill-filesystem` and
        # `tool-skill` rows and leaves local discovery to each agent preset (see
        # @deepseek-ai/dsh-web-app's patch), so `minimal` alone composes an empty
        # catalog -- no `/` suggestions in the composer and no model-facing
        # `skill` tool. These two rows restore the shipped `standard` preset's
        # arrangement: the filesystem provider contributes `~/.dsh/skills` and
        # the project roots to this agent's registry scope, and `tool-skill`
        # renders the catalog and loader (and owns the `/name` gesture boundary).
        # The skill registry itself stays host-level and shared; these rows only
        # add this preset's provider and consumer.
        - id: skill-filesystem
          name: '@deepseek-ai/dsh-skill-filesystem'

        - id: tool-skill
          name: '@deepseek-ai/dsh-tool-skill'
      '';

      ".dsh/.agent-presets/minimal-agents/preset.yml".text = ''
        name: Minimal-Agents
        description: Minimal's fixed persona and persistent shell, plus workspace instructions (AGENTS.md/CLAUDE.md), local skills (filesystem provider + skill catalog/loader) and the subagent delegation tools (subagent, subagent_fork, send_message, interrupt_agent, list_agents).
        order: 6
      '';
    }
    // lib.optionalAttrs isDesktop {
      # Package caches and the zvec-grep daemon state root are created eagerly
      # so a first sandboxed command cannot race directory creation.
      ".local/share/pnpm/.keep".text = "";
      ".npm/.keep".text = "";
      ".zvec-grep/.keep".text = "";
    }
    // lib.optionalAttrs podmanEnabled {
      # Both interactive dsh surfaces get the same profile patch; managing the
      # files here means `dsh plugin` and the TUI no longer own that layer.
      # podmanEnabled, not isDesktop: these hosts are where the OpenSandbox
      # service the container-world rows talk to actually runs.
      ".dsh/profiles/dsh-tui/cordis.patch.yml".text = dshProfilePatch;
      ".dsh/profiles/web/cordis.patch.yml".text = dshProfilePatch;
    };
  };

  # Hermes' plan providers, merged into the settings home/hermes.nix owns;
  # the upstream module deep-merges `settings` across modules by design.
  services.hermes-agent.settings.providers = hermesProviders;

  # Nested rather than three top-level `xdg.configFile.` keys: statix's
  # repeated-keys lint flags the flat form once the third entry lands, and all
  # three are agent config anyway.
  xdg = {
    configFile = {
      "opencode/opencode.json".text = builtins.toJSON {
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

        # All four MCP servers live under one `mcp` key: statix's repeated-keys
        # lint (W20) flags four sibling `mcp.<name>` assignments, the same
        # reason `xdg.configFile` above is nested rather than flat.
        mcp = {
          # Declarative equivalent of `zg install --target opencode
          # --mcp-transport stdio` from zvec-grep 0.2.2 (install.ts
          # installOpenCodeIntegration). stdio means no daemon to keep up: each
          # opencode session spawns `zg server --stdio`, which manages its own
          # shared daemon. Re-derive both this and `zgGuidance` from the new
          # package (run the installer with HOME pointed at a scratch dir) when
          # bumping zvec-grep's version.
          ${zgServerName} = {
            type = "local";
            # Resolved from the session PATH; zvec-grep is in home.packages.
            command = zgArgv;
            enabled = true;
            timeout = zgTimeoutMs;
          };

          # Declarative equivalent of `ripwire wrap opencode`'s MCP alternative
          # (v0.3.8, wrapMcpJsonOpencode): stdio server, no daemon to keep up --
          # each session spawns `ripwire --mcp`, which manages its own warm
          # index cache. The CLI-first blurb in AGENTS.md below is the
          # recommended path (zero context until invoked); this is the
          # warm-index alternative. `command` is the whole argv here (opencode
          # shape, top-level `mcp`).
          ripwire = {
            type = "local";
            # Resolved from the session PATH; ripwire is in home.packages.
            command = [
              "ripwire"
              "--mcp"
            ];
            enabled = true;
          };

          # Microsoft's Playwright MCP server: headless Chromium with an
          # in-memory profile (the nixpkgs wrapper's isolated default), so a
          # session cannot read or write the user's real browser profile.
          # `command` takes the whole argv here (opencode shape, top-level
          # `mcp`); pwArgv names the store path because a desktop launch may
          # not inherit the interactive PATH.
          ${pwServerName} = {
            type = "local";
            command = pwArgv;
            enabled = true;
            timeout = pwTimeoutMs;
          };

          # Shared agent memory, served once over loopback by the `agent-memory`
          # user service (systemd unit at the end of this file). Remote rather
          # than one stdio server per session: the JSONL store has a single
          # writer, and the whole fleet must share the same graph.
          ${memoryServerName} = {
            type = "remote";
            url = memoryUrl;
            enabled = true;
            # The service is idle-cheap; this only guards a slow first connect.
            timeout = 30000;
          };

          # OpenSandbox sandbox lifecycle/command/file tools. Sandbox creation
          # may pull a multi-GB image, so allow a long tool call; the MCP
          # server's own HTTP timeout is raised in its args for the same reason.
          opensandbox = {
            type = "local";
            # Resolved from the session PATH; the wrapper is in home.packages
            # and injects the per-boot API key (home/opensandbox.nix).
            command = [
              "opensandbox-mcp"
              "--request-timeout-seconds"
              "900"
            ];
            enabled = true;
            timeout = 960000;
          };
        };

        # Models picked from the TUI's model list (`/models`) live in opencode's
        # own sqlite state, so the last selection survives sessions without
        # fighting the Nix-managed config. Listing this provider is what puts
        # `cloudflare-workers-ai` in that list -- the rest of the
        # model metadata (262k context, tool calls, vision, $0.45/$3.20 per Mtok)
        # comes from models.dev, and the endpoint is built from
        # CLOUDFLARE_ACCOUNT_ID with CLOUDFLARE_API_KEY as the token.
        provider = {
          # Local Ollama. models.dev carries `ollama-cloud`, not a discoverable
          # local `ollama`, so the endpoint and the local tag are declared here.
          # The served windows mirror the pi/dsh entries: 153600 of the 160k
          # tag's 163840 and 251904 of the 262k tag's 262144, leaving room for
          # output and the 20k compaction reserve.
          # opencode2 reads this same config directory.
          ollama = {
            npm = "@ai-sdk/openai-compatible";
            name = "Ollama (local)";
            options = {
              baseURL = "http://127.0.0.1:11434/v1";
              apiKey = "ollama"; # Ollama ignores it; the SDK wants a value
            };
            models."orcarouter/Qwen3.8-27B-Uncensored:160k" = {
              name = "Qwen3.8 27B Uncensored (160k)";
              attachment = true;
              reasoning = true;
              tool_call = true;
              limit = {
                context = 153600;
                output = 16384;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                ];
                output = [ "text" ];
              };
            };
            models."qwen3.8-cyber-iq4xs:262k" = {
              name = "Qwen3.8 27B Cyber IQ4_XS (262k)";
              attachment = true;
              reasoning = true;
              tool_call = true;
              limit = {
                context = 251904;
                output = 16384;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                ];
                output = [ "text" ];
              };
            };
          };
          cloudflare-workers-ai.models.${cfModel} = { };

          # Union Alpha Free. models.dev already carries it for both OpenCode
          # provider ids; the explicit declarations pin the free metadata so a
          # stale catalog cache cannot drop the model. The Zen row below is the
          # client-gated free tier, the Go row the one the exported
          # OPENCODE_API_KEY authenticates; loadKey above explains the split.
          opencode.models.${unionAlpha.opencodeId} = unionAlphaOpencodeModel;
          "opencode-go".models.${unionAlpha.opencodeId} = unionAlphaOpencodeModel;

          # DeepSeek direct API (OpenAI-compatible endpoint).
          deepseek = {
            npm = "@ai-sdk/openai-compatible";
            name = "DeepSeek";
            options = {
              baseURL = "https://api.deepseek.com/v1";
              apiKey = "{env:DEEPSEEK_API_KEY}";
            };
            models."deepseek-v4.1-flash-expires-on-0910" = {
              name = "DeepSeek V4.1 Flash";
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1000000;
                output = 384000;
              };
            };
          };

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

          # OpenRouter's copy of the same free stealth model. Vision and tool
          # calls come from models.dev; `reasoning = false` is pinned because
          # the model's advertised parameters omit reasoning (unlike the
          # OpenCode copy above), and a truthy value would only make opencode
          # expose a thinking picker for a capability the endpoint lacks.
          openrouter.models.${unionAlpha.openrouterId} = {
            name = "Union Alpha";
            reasoning = false;
            tool_call = true;
            attachment = true;
            limit = {
              context = unionAlpha.contextWindow;
              output = unionAlpha.maxTokens;
            };
            modalities = {
              input = [
                "text"
                "image"
              ];
              output = [ "text" ];
            };
          };

          # CrofAI's OpenAI-compatible endpoint. The catalog is not in
          # models.dev, so the metadata travels with the provider.
          CrofAI = crofOpencodeProvider;
        }
        // qwenProvider;
      };

      # opencode loads the config-dir AGENTS.md globally; the body is shared with
      # pi's copy below.
      "opencode/AGENTS.md".text = ''
        <!-- ZVEC_GREP_START -->
        ${zgGuidance}
        <!-- ZVEC_GREP_END -->
        <!-- RIPWIRE_START -->
        ${ripwireGuidance}
        <!-- RIPWIRE_END -->
        <!-- AGENT_BROWSER_START -->
        ${agentBrowserGuidance}
        <!-- AGENT_BROWSER_END -->
        <!-- MEMORY_START -->
        ${memoryGuidance}
        <!-- MEMORY_END -->
        <!-- OPENSANDBOX_START -->
        ${opensandboxGuidance}
        <!-- OPENSANDBOX_END -->
      '';

      # opencode's documented global skill root, under the config directory
      # the stable and beta CLIs share. A copy here makes the setup independent
      # of opencode's `~/.claude/skills` auto-discovery fallback.
      "opencode/skills/agent-browser/SKILL.md".text = agentBrowserSkill;

      # The same for opencode2, which shares this config directory with the
      # stable CLI: it scans both `skill/` and `skills/` under a config root
      # and follows the directory symlink.
      "opencode/skills/security-audit".source = securityAuditSkill;

      # The same server in the host-agnostic format pi-mcp-adapter reads. The
      # adapter is already installed (npm:pi-mcp-adapter in ~/.pi/agent/npm) and
      # loads this user-global file automatically as the lowest-precedence of its
      # six config layers -- no `imports` entry, and opencode keeps reading its own
      # file untouched.
      #
      # Differences from the opencode block, both from the adapter's own schema:
      #   - `command` is only the executable, argv goes to `args`. The adapter does
      #     understand opencode's array form, but only when importing a host config
      #     (/mcp setup); entries read from a standard MCP file are passed through
      #     verbatim, so an array `command` here would spawn nothing.
      #   - opencode's `timeout` is `requestTimeoutMs`. Same 600s, because a cold
      #     index build is the slow call -- at the cost of a wedged server now
      #     taking 10 minutes, rather than the SDK default, to time out on every
      #     request including the lazy connect.
      #   - `enabled = true` has no counterpart: presence enables a server, and only
      #     a literal `"disabled": true` takes it out. `/mcp disable` writes that
      #     flag to the project-local `.pi/mcp.json` and never rewrites this file --
      #     which it could not do anyway, being a read-only store symlink.
      #
      # `lifecycle` is left at the adapter's default (`lazy`): it starts
      # `zg server --stdio` on the first call and idle-drops it after 10 minutes,
      # keeping the ~200-token proxy tool in context instead of every zvec-grep
      # schema. Tool names come out as `zvec_grep_zvec_grep_*`, matching
      # `zgGuidance`, so that text is worth re-checking if the server name or the
      # adapter's `toolPrefix` setting ever changes.
      "mcp/mcp.json".text = builtins.toJSON {
        # All four servers under one `mcpServers` key (statix W20; see the
        # opencode block above).
        mcpServers = {
          ${zgServerName} = {
            command = builtins.head zgArgv;
            args = builtins.tail zgArgv;
            requestTimeoutMs = zgTimeoutMs;

            # The proxy's search is the only way pi ever sees these tools, so the
            # keywords carry the words pi's header above promises. Keys are tool
            # names or globs -- matched against both the original and the prefixed
            # name -- and the values are never shown to the model, they only rank
            # `mcp({ search })` results.
            searchKeywords."*" = [
              "workspace"
              "codebase"
              "code"
              "semantic"
              "similarity"
              "index"
              "grep"
              "ripgrep"
              "regex"
              "search"
            ];
          };

          # The same server in the host-agnostic format pi-mcp-adapter reads:
          # `command` is only the executable, argv goes to `args`. No timeout
          # override: ripwire parses ~1s cold and answers warm in ~0.1s, so the
          # adapter default is plenty, unlike zvec-grep's cold index builds.
          #
          # Tool names come out as `ripwire_<verb>` (server name prefix +
          # upstream verb, e.g. `ripwire_for`, `ripwire_explore`), matching what
          # pi's AGENTS.md header above promises.
          ripwire = {
            command = "ripwire";
            args = [ "--mcp" ];

            searchKeywords."*" = [
              "codebase"
              "map"
              "callgraph"
              "callers"
              "impact"
              "blast"
              "radius"
              "orient"
              "explore"
              "symbols"
            ];
          };

          # Microsoft's Playwright MCP server, reached through the same lazy
          # proxy as the others: only the `mcp` tool is in context until a
          # search names it. The browser is headless Chromium with an in-memory
          # profile (the nixpkgs wrapper's isolated default), so it cannot read
          # or write the user's real browser profile. Tool names come out as
          # `playwright_browser_*`.
          ${pwServerName} = {
            command = builtins.head pwArgv;
            args = builtins.tail pwArgv;
            requestTimeoutMs = pwTimeoutMs;

            searchKeywords."*" = [
              "browser"
              "playwright"
              "web"
              "page"
              "navigate"
              "click"
              "form"
              "screenshot"
              "scrape"
              "automation"
              "ui"
              "test"
            ];
          };

          # Shared agent memory: the remote StreamableHTTP `agent-memory` service,
          # reached through the adapter's lazy proxy like the others, so none of
          # its schemas sit in context until `mcp({ search: "memory" })` is called.
          # Tool names come out as `memory_<tool>` (server name + upstream name).
          ${memoryServerName} = {
            url = memoryUrl;
            httpTransport = "streamable-http";
            searchKeywords."*" = [
              "memory"
              "remember"
              "recall"
              "knowledge"
              "graph"
              "entity"
              "entities"
              "relation"
              "relations"
              "observation"
              "fact"
              "decision"
            ];
          };

          # OpenSandbox: the local rootless-podman sandbox platform. A sandbox
          # create can pull a multi-GB image, so keep both the HTTP request and
          # the adapter's tool-call timeout long. Lazy by default, so only the
          # proxy tool is in context until `mcp({ search: "sandbox" })`.
          opensandbox = {
            command = "opensandbox-mcp";
            args = [
              "--request-timeout-seconds"
              "900"
            ];
            requestTimeoutMs = 960000;
            searchKeywords."*" = [
              "sandbox"
              "container"
              "podman"
              "isolated"
              "isolate"
              "execute"
              "execution"
              "code"
              "shell"
              "install"
              "untrusted"
              "work"
            ];
          };
        };
      };
    };
  };

  # The shared agent-memory server. One process owns the JSONL graph and
  # exposes it over loopback Streamable HTTP (`/mcp`) and SSE (`/sse`); every
  # harness registers it as a remote server, so writes never race. Runs on all
  # three hosts (each keeps its own preserved store), not just the desktop.
  #
  # The HTTP transport runs stateless (`--stateless`): each request is served
  # on its own transport with no Mcp-Session-Id, so dsh's MCP SDK v2 client
  # (and any other spec-conformant client) can talk to it without holding a
  # session. The stdio backend below is untouched -- one persistent
  # `mcp-server-memory` process is still the single writer for the JSONL graph;
  # only the client-facing sessions go away. Do not drop this: the proxy
  # default is a stateful session per client, which is pure state a restart
  # throws away.
  systemd.user.services = {
    agent-memory = {
      Unit = {
        Description = "Shared agent-memory knowledge-graph MCP server";
        # Survive a slow start without tripping the default restart-rate limit.
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        # The store directory must exist before the server opens its file; %h is
        # expanded by systemd to the invoking user's home.
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.local/share/agent-memory";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.mcp-proxy}/bin/mcp-proxy"
          "--host"
          "127.0.0.1"
          "--port"
          (toString memoryPort)
          "--stateless"
          "-e"
          "MEMORY_FILE_PATH"
          memoryFileSpec
          "--"
          "${pkgs.mcp-server-memory}/bin/mcp-server-memory"
        ];
        Restart = "always";
        RestartSec = 2;
        TimeoutStopSec = 10;
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # dsh-web is kept here rather than in home/services.nix because its
    # ExecStart has to name the wrapped package defined above; it is gated to
    # the desktop, which is where the matching Tailscale Serve unit exists.
    dsh-web = lib.mkIf isDesktop {
      Unit = {
        Description = "DeepSeek Harness web UI";
        # The service has to survive a boot where tailscaled is not ready to
        # answer `tailscale status` yet; disable the default restart-rate limit.
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        # dsh's built-in sandbox-local uses process.cwd() as the
        # workspace-write root. The web front door exists to work on this
        # flake, so root it there; other project directories belong in
        # `osb-work` containers, not in this host shell.
        WorkingDirectory = "/persistent/etc/nixos";
        # Name the pinned plugin revision in the unit text so changing it
        # restarts this long-lived web process during activation. Without the
        # marker, an activation that only rewrites the copied module would
        # leave the old plugin in memory until the next boot.
        Environment = [ "DSH_OPENSANDBOX_PLUGIN=${pkgs.dsh-opensandbox}" ];
        ExecStart = lib.getExe dshWebServe;
        Restart = "always";
        RestartSec = 2;
        TimeoutStopSec = 10;
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };

  };
}
