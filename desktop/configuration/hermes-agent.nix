{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # The nixos config this machine is built from. The agent's hooks lint it and
  # its session-context hook reports on it, so it is named once here.
  nixosRepo = "/persistent/etc/nixos";

  # State the hooks own. Not config: just per-session markers so the context
  # hook fires once per session instead of once per LLM call.
  hookState = "${config.services.hermes-agent.stateDir}/hook-state";

  # ── Immutable skills ─────────────────────────────────────────────────────
  # HERMES_HOME/skills is agent-writable by design (Hermes creates and edits
  # skills as it learns). Anything that must survive the agent editing it goes
  # through skills.external_dirs pointing at a /nix/store path instead —
  # read-only for everyone, rebuilt only by nixos-rebuild.
  #
  # devops/cli is deliberately absent: despite the name it is the inference.sh
  # CLI, not a general shell skill.
  optionalSkills = {
    devops = [
      "docker-management"
      "watchers"
    ];
    security = [
      "oss-forensics"
      "web-pentest"
    ];
    software-development = [
      "code-wiki"
      "rest-graphql-debug"
      "subagent-driven-development"
    ];
    # Both are keyless — no API token to leak into the agent's environment.
    research = [
      "duckduckgo-search"
      "searxng-search"
    ];
    mcp = [
      "fastmcp"
      "mcporter"
    ];
    web-development = [ "cloudflare-temporary-deploy" ];
  };

  optionalSkillTree = pkgs.runCommand "hermes-optional-skills" { } (
    lib.concatStrings (
      lib.mapAttrsToList (
        category: names:
        "mkdir -p $out/${category}\n"
        + lib.concatMapStrings (
          name: "cp -r ${inputs.hermes-agent}/optional-skills/${category}/${name} $out/${category}/${name}\n"
        ) names
      ) optionalSkills
    )
  );

  # Host-specific procedural knowledge. Written here rather than in
  # HERMES_HOME so it cannot drift from the machine it describes.
  hostSkill = pkgs.writeTextDir "nixos/nixos-host/SKILL.md" ''
    ---
    name: nixos-host
    description: How to work on this NixOS machine — flake layout, immutable rebuild workflow, and running any tool without installing it.
    version: 1.0.0
    license: MIT
    platforms: [linux]
    metadata:
      hermes:
        tags: [nixos, nix, flake, sysadmin, immutable]
    ---

    # Working on this NixOS host

    This machine is declarative. The running system is a build product of a
    flake; nothing installed by hand survives a rebuild.

    ## Layout

    - Flake root: `${nixosRepo}` (also reachable as `/etc/nixos`). Git repo.
    - Hosts: `desktop/`, `laptop/`, `steamdeck/`. Shared code: `modules/`,
      `home/` (home-manager for user `codebam`).
    - Secrets: sops-nix, `secrets/`, `.sops.yaml`. Never read, print, or commit
      decrypted secret material.
    - Lint config: `statix.toml` at the repo root.

    ## Running tools

    Everything in nixpkgs is available without installing anything:

    ```bash
    nix run nixpkgs#<package> -- <args>   # exact package known
    , <command>                           # command known, package unknown
    nix shell nixpkgs#<a> nixpkgs#<b>     # several tools for one shell
    ```

    `,` (comma) resolves a command name to its package via a store-baked
    nix-index database — no network, no cache priming. The `nixpkgs` flake
    registry entry is pinned to this system's own nixpkgs input, so
    `nix run nixpkgs#x` matches the packages the system was built from and
    resolves without a network fetch.

    Prefer this over asking the operator to add a package. Only propose a
    `environment.systemPackages` / `home.packages` edit when the tool must
    persist across reboots or be on PATH for a service.

    ## Privilege escalation

    There is no `sudo` on this host and there is no `doas`. Use `run0`:

    ```bash
    run0 <command>            # run as root
    run0 --user=<name> <cmd>  # run as another user
    ```

    `run0` is systemd's escalation tool. It authenticates through polkit and
    runs the command in a fresh transient unit rather than inheriting this
    shell's environment, so pass absolute paths and do not assume exported
    variables, the current `PATH`, or the working directory carry over.

    Writing `sudo` is not a small style slip here: the binary does not exist,
    so the command fails with "sudo: command not found" and whatever came after
    it in a `&&` chain never runs. A hook blocks `sudo` and says this.

    ## Editing and validating

    ```bash
    nixfmt path/to/file.nix              # format (required; a hook enforces it)
    statix check path/to/file.nix        # lint
    deadnix path/to/file.nix             # dead code
    nix flake check ${nixosRepo}         # whole-flake evaluation
    nixos-rebuild build --flake ${nixosRepo}#<host>   # full build, no activation
    ```

    Search NixOS options and packages through the `mcp-nixos` MCP tools rather
    than guessing an option name — they query the real option index.
    `manix "<term>"` is the offline fallback.

    The `nix-lsp` MCP server runs nixd over this repo. Use it for "what is
    this", "where else is this used", and for reading diagnostics after an
    edit — it resolves through the module system, which ripgrep cannot. Keep
    ripgrep for text and filename searches.

    ## Activation is operator-only

    `nixos-rebuild switch`, `nixos-rebuild boot`, `nix-collect-garbage`, and
    `nh clean` are blocked by a hook. They mutate the running system or delete
    rollback generations, which is the operator's call, not yours.

    Build and verify as far as `nixos-rebuild build`, then report the exact
    command for the operator to run.

    ## Conventions

    - Format with `nixfmt` and keep `statix check` clean before finishing.
    - Match the surrounding style: attrs over `with`, explicit module args.
    - Impermanence is in use (`preservation`). A path that must survive reboot
      needs an entry in the preservation module — writing it is not enough.
  '';

  # FlareSolverr is a plain HTTP service on loopback, not an MCP server, so
  # nothing advertises it to the model. This skill is the only thing that
  # tells the agent it exists and how to call it.
  flaresolverrSkill = pkgs.writeTextDir "research/flaresolverr/SKILL.md" ''
    ---
    name: flaresolverr
    description: Fetch a page that is behind a Cloudflare or DDoS-Guard challenge, when a normal fetch returns a "Just a moment..." interstitial or HTTP 403/503.
    version: 1.0.0
    license: MIT
    platforms: [linux]
    metadata:
      hermes:
        tags: [web, scraping, cloudflare, http]
    ---

    # FlareSolverr

    A local proxy that drives a headless Chrome through a bot-check
    interstitial and returns the real page plus the cookies that got it.

    Endpoint: `http://127.0.0.1:8191/v1`. Loopback only, no auth, no key.

    ## When to reach for it

    Only after a normal fetch has already failed. The `fetch` MCP tool is
    faster, cheaper, and returns markdown instead of raw HTML. Escalate here
    when that returns:

    - a body containing `Just a moment...`, `Checking your browser`, or
      `Enable JavaScript and cookies to continue`
    - HTTP 403 or 503 from a site that works in a real browser
    - `cf-mitigated: challenge` in the response headers

    A 404, a paywall, or a login wall is not a challenge. FlareSolverr will
    not help and you should say so instead of retrying.

    ## Fetching a page

    ```bash
    curl -sS -X POST http://127.0.0.1:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd": "request.get", "url": "https://example.com/", "maxTimeout": 60000}' \
      | jq -r '.solution.response'
    ```

    The reply is JSON: `.status` is `ok` or `error`, `.message` explains a
    failure, `.solution.response` is the HTML, `.solution.status` is the
    upstream HTTP code, `.solution.cookies` and `.solution.userAgent` are what
    you need to keep fetching that host yourself.

    `.solution.response` is full HTML and is usually large. Pipe it through a
    converter rather than reading it whole:

    ```bash
    ... | jq -r '.solution.response' | ${lib.getExe pkgs.html2text} | head -200
    ```

    ## POST

    ```bash
    curl -sS -X POST http://127.0.0.1:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd": "request.post", "url": "https://example.com/search",
           "postData": "q=nixos&page=1", "maxTimeout": 60000}'
    ```

    `postData` is a urlencoded string, not an object. The content type is
    always `application/x-www-form-urlencoded`; JSON bodies are not supported.

    ## Reusing a session

    Each request otherwise starts a fresh browser, which costs several
    seconds. For more than two or three requests to one host, create a
    session and pass its name:

    ```bash
    curl -sS -X POST http://127.0.0.1:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd": "sessions.create", "session": "work"}'
    # ... then "session": "work" alongside cmd in each request.get
    curl -sS -X POST http://127.0.0.1:8191/v1 \
      -H 'Content-Type: application/json' \
      -d '{"cmd": "sessions.destroy", "session": "work"}'
    ```

    Destroy the session when done. A live session holds a Chrome process open;
    the container is capped at 2GB and will start failing if sessions pile up.

    ## Limits and manners

    - Each solve takes 5-40s. It is not a substitute for a normal fetch.
    - `maxTimeout` is in milliseconds and caps the solve, not the download.
    - The container ignores robots.txt because it is a raw browser. You should
      not: check whether the site permits automated access, and do not use
      this to defeat a paywall, a login, or an explicit rate limit.
    - Do not loop it over a URL list to scrape a site in bulk. It is for
      getting past a check on a page you were already going to read once.
    - If it fails twice on one URL, stop and report it. Cloudflare's harder
      tiers are not solvable this way and retrying just burns minutes.

    ## When it is not running

    ```bash
    run0 systemctl status podman-flaresolverr.service
    ```

    Starting it is fine; a persistent failure is the operator's problem, not
    something to work around with another scraper.
  '';

  hermesSkills = pkgs.symlinkJoin {
    name = "hermes-skills";
    paths = [
      optionalSkillTree
      hostSkill
      flaresolverrSkill
    ];
  };

  # ── Immutable hooks ──────────────────────────────────────────────────────
  # Shell hooks are referenced by absolute store path, so the allowlist entry
  # is pinned to exact script content: editing a hook changes its path, which
  # is a new consent decision rather than a silent swap.
  mkHook =
    name: runtimeInputs: text:
    lib.getExe (pkgs.writeShellApplication { inherit name runtimeInputs text; });

  guardTerminal = mkHook "hermes-hook-guard-terminal" [ pkgs.jq ] ''
    payload=$(cat)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')

    block() {
      jq -cn --arg r "$1" '{decision: "block", reason: $r}'
      exit 0
    }

    match() {
      printf '%s' "$cmd" | grep -qE "$1"
    }

    # Where a word is the command being run rather than an argument to one.
    # Without this, "grep sudo /etc/passwd" trips the sudo rule below.
    at_start='(^[[:space:]]*|[;&|(][[:space:]]*)'

    if match '(^|[;&|[:space:]])rm[[:space:]]+(-[[:alnum:]]*[rR][[:alnum:]]*[fF]|-[[:alnum:]]*[fF][[:alnum:]]*[rR]|-[rR][[:space:]]+-[fF]|-[fF][[:space:]]+-[rR])[[:space:]]+(/|/\*|~|[$]HOME)([[:space:]]|$)'; then
      block "blocked: recursive force-delete of a filesystem or home root."
    fi

    if match 'nixos-rebuild([[:space:]]|[^;&|])*(switch|boot)([[:space:]]|$)'; then
      block "blocked: 'nixos-rebuild switch' and 'boot' activate a new system generation, which is operator-only on this host. Use 'nixos-rebuild build --flake ${nixosRepo}#<host>' or 'nixos-rebuild dry-activate' to verify, then report the switch command for the operator to run."
    fi

    # The back door around the rule above: build, then activate the result
    # directly.
    if match 'switch-to-configuration([[:space:]]|[^;&|])*(switch|boot)([[:space:]]|$)'; then
      block "blocked: activating a built configuration is the same operator-only step as 'nixos-rebuild switch'. Report the command instead of running it."
    fi

    if match "$at_start"'(nix-collect-garbage|nix store gc|nh clean)([[:space:]]|$)'; then
      block "blocked: garbage collection deletes rollback generations. Operator-only."
    fi

    if match '(>|>>)[[:space:]]*/nix/store|(^|[;&|[:space:]])(rm|chmod|chown|mv)[[:space:]][^;&|]*/nix/store'; then
      block "blocked: /nix/store is immutable. Change the nix expression in ${nixosRepo} and rebuild instead."
    fi

    # Last, so the rules above keep their more specific reasons: there is no
    # sudo on this host. Left to run it would fail with "command not found"
    # and silently break the rest of an && chain.
    if match "$at_start"'sudo([[:space:]]|$)'; then
      block "blocked: this host has no sudo (and no doas). Use 'run0 <command>' instead. run0 runs the command in a fresh transient unit, so pass absolute paths and do not rely on the current PATH, exported variables, or working directory."
    fi

    printf '{}\n'
  '';

  formatOnWrite =
    mkHook "hermes-hook-format-on-write"
      [
        pkgs.jq
        pkgs.nixfmt
        pkgs.shfmt
        pkgs.ruff
      ]
      ''
        payload=$(cat)
        path=$(printf '%s' "$payload" | jq -r '.tool_input.path // empty')

        if [ -n "$path" ] && [ -f "$path" ]; then
          case "$path" in
            *.nix) nixfmt "$path" >/dev/null 2>&1 || true ;;
            *.sh|*.bash) shfmt -w -i 2 -ci "$path" >/dev/null 2>&1 || true ;;
            *.py) ruff format "$path" >/dev/null 2>&1 || true ;;
          esac
        fi

        printf '{}\n'
      '';

  sessionContext =
    mkHook "hermes-hook-session-context"
      [
        pkgs.jq
        pkgs.git
        pkgs.coreutils
      ]
      ''
        payload=$(cat)
        session=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' | tr -cd 'A-Za-z0-9._-')

        # pre_llm_call fires on every turn; the host facts only need saying once.
        mkdir -p ${hookState}
        marker="${hookState}/ctx-''${session:-unknown}"
        if [ -e "$marker" ]; then
          printf '{}\n'
          exit 0
        fi
        : > "$marker"

        generation=$(readlink -f /run/current-system 2>/dev/null || echo unknown)
        branch=$(git -C ${nixosRepo} rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
        head=$(git -C ${nixosRepo} rev-parse --short HEAD 2>/dev/null || echo unknown)
        dirty=$(git -C ${nixosRepo} status --porcelain 2>/dev/null | wc -l)

        ctx=$(printf 'Host: NixOS, declarative. Flake: %s (branch %s @ %s, %s uncommitted paths). Running generation: %s. Any nixpkgs tool is available via "nix run nixpkgs#<pkg>" or ", <command>" - do not ask for installs to run something once. There is no sudo on this host: escalate with "run0 <command>". System activation (nixos-rebuild switch/boot) and garbage collection are blocked and operator-only. Load the nixos-host skill before editing the flake.' \
          "${nixosRepo}" "$branch" "$head" "$dirty" "$generation")

        jq -cn --arg c "$ctx" '{context: $c}'
      '';

  verifyNix =
    mkHook "hermes-hook-verify-nix"
      [
        pkgs.jq
        pkgs.git
        pkgs.nixfmt
        pkgs.statix
      ]
      ''
        cd ${nixosRepo} 2>/dev/null || {
          printf '{}\n'
          exit 0
        }

        changed=$(git status --porcelain -- '*.nix' 2>/dev/null | awk '{print $NF}')
        if [ -z "$changed" ]; then
          printf '{}\n'
          exit 0
        fi

        problems=""
        while IFS= read -r f; do
          [ -f "$f" ] || continue
          if ! nixfmt --check "$f" >/dev/null 2>&1; then
            problems="''${problems}unformatted: $f"$'\n'
          fi
          lint=$(statix check "$f" 2>&1) || problems="''${problems}statix $f:"$'\n'"$lint"$'\n'
        done <<< "$changed"

        if [ -n "$problems" ]; then
          msg=$(printf 'Nix changes are not clean yet. Run nixfmt on each unformatted file and fix the statix lints, then finish:\n\n%s' "$problems")
          jq -cn --arg m "$msg" '{action: "continue", message: $m}'
        else
          printf '{}\n'
        fi
      '';

  # ── Viewport profile ───────────────────────────────────────────────────
  # A hermes profile is a fully independent HERMES_HOME: its own config.yaml,
  # sessions, memories, and skills. `hermes -p viewport` picks it up.
  #
  # It exists so rust-analyzer is only ever live for Viewport work. nix-lsp is
  # pinned to the flake with --workspace, so on a Rust tree it answers about
  # the wrong repo — plausibly and wrongly. Separating the profiles is what
  # keeps each language server pointed at the tree it understands.
  hermesHome = "${config.services.hermes-agent.stateDir}/.hermes";
  viewportProfile = "${hermesHome}/profiles/viewport";

  # The agent gets its own clone, over https and read-only credentials.
  # /home/codebam is 0700, so the hermes user cannot traverse it — pointing a
  # language server at the real working tree would connect and then fail every
  # query with EACCES. The tradeoff is drift: this is a sibling checkout, not
  # the tree being edited.
  viewportClone = "${config.services.hermes-agent.stateDir}/workspace/Viewport";
  viewportRepo = "https://github.com/codebam/viewport-smithay.git";

  # rust-analyzer needs rustc, cargo, and the bindgen/pkg-config environment to
  # resolve the crate graph; a bare binary on PATH resolves nothing. The
  # project's own devShell already assembles exactly that, so borrow it.
  #
  # `.#rust` is named explicitly and must stay that way — a bare `nix develop`
  # selects devShells.default, which builds WPE WebKit and takes hours.
  # rust-analyzer itself is passed by store path because devShells.rust does
  # not carry it (only the workstation shell does).
  rustAnalyzer = pkgs.writeShellApplication {
    name = "hermes-rust-analyzer";
    runtimeInputs = [
      config.nix.package
      pkgs.git
    ];
    text = ''
      exec nix develop "${viewportClone}#rust" --command ${lib.getExe pkgs.rust-analyzer} "$@"
    '';
  };

  # Servers worth having whatever the agent is working on.
  mcpCommon = {
    # Fetches a URL and returns markdown, chunked via start_index. Pairs
    # with the duckduckgo/searxng skills: they find the URL, this reads it
    # without spending the context window on tag soup.
    fetch = {
      command = lib.getExe pkgs.mcp-server-fetch;
      args = [
        "--user-agent"
        "hermes-agent (+https://github.com/NousResearch/hermes-agent)"
      ];
      timeout = 60;
    };

    # Version-accurate library documentation, pulled on demand. Covers the
    # ground mcp-nixos does not: everything that is not a NixOS option.
    #
    # The key is interpolated by Hermes at connect time from the process
    # environment, which systemd fills from the sops-decrypted
    # environmentFiles below. Written as a literal ${...} placeholder on
    # purpose — putting the key itself here would put it in /nix/store,
    # world-readable.
    context7 = {
      command = lib.getExe pkgs.context7-mcp;
      env.CONTEXT7_API_KEY = "\${CONTEXT7_API_KEY}";
      timeout = 60;
    };

    # Models have no clock. Two tools, negligible schema cost.
    time = {
      command = lib.getExe pkgs.mcp-server-time;
      args = [
        "--local-timezone"
        config.time.timeZone
      ];
      timeout = 15;
    };
  };

  # Default profile only: this host and its flake.
  mcpNixos = {
    nixos = {
      command = lib.getExe pkgs.mcp-nixos;
      # Queries the NixOS option/package index so the agent looks options up
      # instead of inventing them.
      timeout = 60;
    };

    # LSP over MCP: definitions, references, and diagnostics that resolve
    # through the module system instead of ripgrep guesses.
    #
    # nixd is passed by absolute store path: MCP children get a filtered
    # environment, so do not assume this service's PATH reaches them.
    nix-lsp = {
      command = lib.getExe pkgs.mcp-language-server;
      args = [
        "--workspace"
        nixosRepo
        "--lsp"
        (lib.getExe pkgs.nixd)
      ];
      timeout = 120;
    };
  };

  # Viewport profile only.
  mcpViewport.rust-lsp = {
    command = lib.getExe pkgs.mcp-language-server;
    args = [
      "--workspace"
      viewportClone
      "--lsp"
      (lib.getExe rustAnalyzer)
    ];
    # First call pays for the devShell realisation and a cold cargo metadata
    # pass over smithay's dependency graph. Later calls are fast.
    timeout = 300;
  };

  # The module renders services.hermes-agent.mcpServers into settings for the
  # default profile. The viewport profile's config.yaml is written here
  # directly, so the same shape has to be produced by hand.
  renderMcp = lib.mapAttrs (
    _name: srv:
    {
      inherit (srv) command timeout;
      args = srv.args or [ ];
      enabled = true;
    }
    // lib.optionalAttrs (srv ? env) { inherit (srv) env; }
  );

  # Hooks that apply wherever the agent runs. verifyNix is deliberately absent:
  # it lints *.nix in the flake, which is noise in a Rust tree.
  commonHooks = {
    pre_tool_call = [
      {
        matcher = "terminal";
        command = guardTerminal;
        timeout = 10;
      }
    ];
    post_tool_call = [
      {
        matcher = "write_file|patch";
        command = formatOnWrite;
        timeout = 30;
      }
    ];
    pre_llm_call = [
      {
        command = sessionContext;
        timeout = 15;
      }
    ];
  };

  baseSettings = {
    model = {
      base_url = "https://openrouter.ai/api/v1";
      default = "~deepseek/deepseek-v4-flash-latest";
    };
    toolsets = [ "all" ];
    terminal = {
      backend = "local";
      timeout = 600;
    };
    display = {
      compact = false;
    };
    memory = {
      memory_enabled = true;
      user_profile_enabled = true;
    };

    # Read-only skill tree. Local HERMES_HOME/skills still wins on a name
    # collision and still takes agent-created skills; these cannot be edited
    # away by the agent or by `hermes update`.
    skills.external_dirs = [ "${hermesSkills}" ];

    hooks = commonHooks;

    # The gateway and cron run with no TTY, so the first-use consent prompt
    # can never be answered there. Safe here only because every `command:`
    # above is an absolute /nix/store path: content-addressed, root-owned,
    # and unwritable by the agent. Do not point a hook at a mutable path
    # (HERMES_HOME, /tmp, a home directory) while this is true.
    hooks_auto_accept = true;
  };

  # Written whole rather than merged: the module's config-merge script only
  # covers the default profile, so this file is the single source of truth for
  # the viewport one. Symlinked from the store, so the agent cannot edit it.
  viewportConfig = (pkgs.formats.yaml { }).generate "hermes-viewport-config.yaml" (
    baseSettings
    // {
      mcp_servers = renderMcp (mcpCommon // mcpViewport);
      terminal = baseSettings.terminal // {
        cwd = viewportClone;
      };
    }
  );
in
{
  # `nix run nixpkgs#x` and `,` resolve against the flake registry. Unpinned it
  # fetches whatever nixos-unstable is right now, which needs network and can
  # disagree with what this system was built from. Pinning it to our own input
  # makes the agent's ad-hoc tooling reproducible and offline.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # ── Tools ──────────────────────────────────────────────────────────────
    # These are on PATH for the terminal tool, cron jobs, and skills without a
    # `nix run` round-trip. Anything not here is still one `, <cmd>` away.
    extraPackages = [
      config.nix.package
      inputs.nix-index-database.packages.${system}.comma-with-db
    ]
    ++ (with pkgs; [
      # Nix toolchain
      nixfmt
      statix
      deadnix
      manix
      nix-output-monitor
      nix-tree
      nix-diff
      nvd
      nurl
      nix-init
      # Source navigation — cheaper than reading files one by one
      ripgrep
      fd
      universal-ctags
      repomix
      tree
      bat
      eza
      # Data wrangling
      jq
      yq-go
      gnused
      gawk
      coreutils
      # Network / VCS
      git
      gh
      curl
      wget
      # Languages and their formatters
      python3
      uv
      nodejs
      ruff
      shellcheck
      shfmt
    ]);

    # ── MCP ────────────────────────────────────────────────────────────────
    # Every tool schema here is in the prompt on every turn, so this list is
    # deliberately short. Anything reachable with one shell command stays a
    # shell command. rust-lsp is not here on purpose — it lives in the
    # viewport profile below.
    mcpServers = mcpCommon // mcpNixos;

    settings = baseSettings // {
      hooks = commonHooks // {
        # Default profile only: the flake is the tree this lints.
        pre_verify = [
          {
            command = verifyNix;
            timeout = 90;
          }
        ];
      };
    };
  };

  # ── Viewport profile plumbing ────────────────────────────────────────────
  # A profile is just a directory hermes recognises; `hermes profile create`
  # would bootstrap these, but doing it here keeps the profile declarative and
  # reproducible instead of depending on a one-time imperative command.
  systemd = {
    tmpfiles.rules =
      let
        # 2770, matching the rest of HERMES_HOME: the gateway runs as hermes
        # but interactive users in the hermes group run `hermes -p viewport`
        # themselves, and hermes creates subdirectories (logs/curator, ...) on
        # first run. Setgid keeps those group-owned by hermes so both sides
        # keep seeing each other's state.
        dir = d: "d ${d} 2770 hermes hermes - -";
      in
      [
        (dir "${hermesHome}/profiles")
        (dir viewportProfile)
      ]
      ++ map (d: dir "${viewportProfile}/${d}") [
        "memories"
        "sessions"
        "skills"
        "skins"
        "logs"
        "plans"
        "workspace"
        "cron"
        "home"
      ]
      ++ [
        # Store symlink, so the agent cannot edit its own config out from under
        # the module. L+ replaces whatever is there on every activation.
        "L+ ${viewportProfile}/config.yaml - - - - ${viewportConfig}"
        # Profiles do not inherit the default profile's secrets, and the
        # activation script only writes the default .env. Share it rather than
        # decrypting the same sops secret to two places.
        "L+ ${viewportProfile}/.env - - - - ${hermesHome}/.env"
      ];

    # Keeps the agent's clone current. Fetch only — never reset or checkout,
    # since the agent may have work in progress in that tree.
    services.hermes-viewport-clone = {
      description = "Clone or fetch the Viewport tree for the hermes viewport profile";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git ];
      serviceConfig = {
        Type = "oneshot";
        User = "hermes";
        Group = "hermes";
      };
      script = ''
        if [ -d ${viewportClone}/.git ]; then
          git -C ${viewportClone} fetch --prune --all
        else
          git clone --filter=blob:none ${viewportRepo} ${viewportClone}
        fi
      '';
    };

    timers.hermes-viewport-clone = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };

  # addToSystemPackages exports HERMES_HOME=/var/lib/hermes/.hermes system-wide.
  # That tree is 2770/0640 hermes:hermes, so interactive users need the group.
  users.users.codebam.extraGroups = [ "hermes" ];

  # Add hermes desktop app as a home-manager package for codebam
  home-manager.users.codebam = {
    home.packages = [
      inputs.hermes-agent.packages.${system}.desktop
    ];
  };
}
