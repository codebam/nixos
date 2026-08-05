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

  hermesSkills = pkgs.symlinkJoin {
    name = "hermes-skills";
    paths = [
      optionalSkillTree
      hostSkill
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
    mcpServers.nixos = {
      command = lib.getExe pkgs.mcp-nixos;
      # Queries the NixOS option/package index so the agent looks options up
      # instead of inventing them.
      timeout = 60;
    };

    settings = {
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

      hooks = {
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
        pre_verify = [
          {
            command = verifyNix;
            timeout = 90;
          }
        ];
      };

      # The gateway and cron run with no TTY, so the first-use consent prompt
      # can never be answered there. Safe here only because every `command:`
      # above is an absolute /nix/store path: content-addressed, root-owned,
      # and unwritable by the agent. Do not point a hook at a mutable path
      # (HERMES_HOME, /tmp, a home directory) while this is true.
      hooks_auto_accept = true;
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
