{
  config,
  inputs,
  osConfig,
  pkgs,
  lib,
  ...
}:

let
  isDesktop = osConfig.networking.hostName == "nixos-desktop";
  emailMcp = import ./email-mcp.nix { inherit config pkgs; };
  calendarMcp = import ./google-calendar-mcp.nix { inherit config pkgs; };

  # The Cloudflare CLI (`cf`, pkgs/cf.nix) guidance block. home/cf.nix defines
  # the text once (host tiers get `guidance`, the sandbox tiers below get
  # `guidanceSandbox`), and home/hermes.nix interpolates the same strings into
  # its system-prompt hints.
  cfCli = import ./cf.nix;

  # The shared agent-memory knowledge graph (home/agent-memory.nix): the same
  # remote server opencode, dsh, and pi read and write, plus the guidance
  # block those harnesses render -- Hermes registers the
  # `mcp__<server>__<tool>` form like dsh.
  agentMemory = import ./agent-memory.nix;
  memoryGuidance = "\n\n" + agentMemory.guidanceMcp;

  # The hermes package every Hermes surface runs: the CLI on PATH, the
  # services, and the desktop app (which uses its `hermesDesktop` passthru).
  # One binding so the memory provider below is built for THIS venv's
  # interpreter, not a second Python family.
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The native memory provider (home/hermes-agent-memory.nix): the plugin that
  # recalls graph entries into every turn and asks for a review every ten
  # turns, so the graph is used the way Hermes' own MEMORY.md store would have
  # been. Off with everything else on non-desktop hosts.
  memoryProvider = import ./hermes-agent-memory.nix {
    inherit pkgs agentMemory;
    inherit (hermesPackage) python;
    pythonPkgs = hermesPackage.python.pkgs;
  };

  # pm's installed-state rows for the tools nix provides (home/hermes-pm-facts.nix):
  # without them every launch after the first lazily-installed package reports
  # node/npm/ripgrep/ffmpeg as missing and points at a rebuild that cannot fix it.
  pmFacts = import ./hermes-pm-facts.nix {
    inherit pkgs lib;
    lockfile = "${inputs.hermes-agent}/pm/lock.json";
    hermesHome = config.services.hermes-agent.hermesHome;
    node = hermesPackage.hermesNpmLib.nodejs;
    ripgrep = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.pm-ripgrep;
    ffmpeg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.pm-ffmpeg;
  };

  # Standing facts for every Hermes session. The native MEMORY.md/USER.md
  # store is off; this block -- carried through agent.environment_hint /
  # agent.coding_instructions, the only always-on system-prompt surfaces in
  # this revision -- is the always-on layer that took over its job, and the
  # shared agent-memory graph is the memory itself: its provider
  # (home/hermes-agent-memory.nix) recalls relevant entries into every turn
  # and asks for a review on the native ten-turn cadence. Repo state on
  # purpose: reviewed, versioned, identical in every session, never written at
  # runtime. Durable knowledge the user asks Hermes to keep goes to the graph;
  # to change a standing fact, edit this file.
  standingFacts = "\n\n" + ''
    ## Standing facts

    Hermes runs with its native memory store disabled: there is no
    MEMORY.md/USER.md and no memory tool. Memory is the shared agent-memory
    knowledge graph (see the Agent memory section below): its provider recalls
    relevant entries into context before each turn, and every ten turns it
    asks for a review of the session. This block is the always-on layer,
    maintained in /persistent/etc/nixos/home/hermes.nix; durable facts go to
    the graph, not to any Hermes-local file.

    Environment:
    - Hermes config is declarative: `~/.hermes/config.yaml` is GENERATED from
      `/persistent/etc/nixos/home/hermes.nix` (HERMES_MANAGED=home-manager);
      never hand-edit it -- Hermes changes go in that repo. Terminal and file
      commands run on the host shell through Hermes' local backend.
    - Sean's shell is nushell (nu 0.116, reedline, edit_mode=emacs). He does
      NOT use fish, even though `$SHELL` points at fish and a legacy
      `~/.config/fish/config.fish` exists -- never infer the shell from
      `$SHELL`. `config.nu` sources zoxide, direnv, and starship. bash 5.3 for
      scripts. His AGENTS.md forbids `nix profile install` / `nix-env -i`;
      ephemeral tools go through `nix shell nixpkgs#<pkg> -c`.
    - dsh (@deepseek-ai, the DeepSeek Harness) is his coding agent: `~/.dsh`
      holds profiles, settings.yaml, and session logs as zstd-compressed
      JSONL at `~/.dsh/sessions/<project-dir>/<session-id>/session.v3.jsonl.zstd`
      (event types: session, user/message with source.kind=="user",
      assistant/message, tool/call, tool/result with isError).
    - Local services: SearXNG at 127.0.0.1:8081 and the shared agent-memory
      MCP at 127.0.0.1:7979.
    - Build-on-request tools: dsh session-log scan
      `~/.hermes/scripts/dsh-task-scan.sh`; terminal-lesson apparatus
      `~/.hermes/lessons` + `scripts/terminal-lesson-context.sh` (skill
      terminal-skills-daily); NixOS news harvest
      `~/.hermes/scripts/nixos-news-collect.sh` (skill nixos-news-digest).
    - NixOS news sources that work (verified): discourse announcements/events
      JSON + `top.json?period=weekly`,
      nixos.org/blog/{announcements,newsletters,stories}-rss.xml, nixpkgs
      GHSA advisories API, NixOS/nix tags (its releases API is empty -- tags
      carry versions), NixOS/rfcs pulls. DEAD: weekly.nixos.org and
      nixos.org/security. No GitHub token in the env, so the API is 60 calls/hr.
    - Opencode history was imported into Hermes (2026-09-23): 622 sessions
      tagged source='opencode' plus 38 desktop projects. The importer at
      `~/.hermes/scripts/opencode-import/run.sh` is idempotent; re-run it to
      sync new sessions. `~/.hermes/state.db` is ~479MB.

    Sean:
    - Tracks tech news in three areas: AI, programming/dev tooling, and
      consumer electronics; digests grouped by those sections land well.
    - Audits the claims he is given: state the observation time, and re-probe
      live state before asserting something is currently true; he pushes back
      when a present-tense claim rests only on historical evidence.
    - Tracks the NixOS ecosystem (releases/governance, security advisories,
      tooling announcements); prefers cited digests grouped by section, with
      coverage gaps stated explicitly rather than implied completeness.
  '';

  # ── Backing up what the agent wrote ──────────────────────────────────────
  # HERMES_HOME/skills is agent-writable, so everything the agent authors
  # there is unbacked state that a reinstall, an `hermes update`, or a bad
  # edit takes with it. This tool copies exactly those skills into a git work
  # tree and pushes them. The retired modules/services/hermes-agent.nix
  # carried it before hermes moved to the upstream home-manager module; it
  # belongs here, where HERMES_HOME is configured now.
  #
  # "Those" means skills with no counterpart at the same category/name in the
  # pinned hermes-agent source — publishing Nous Research's own skill tree back
  # to GitHub is not a backup, it is a fork nobody asked for.
  #
  # Manual on purpose: it runs as the operator, so it uses the operator's git
  # credentials and no deploy key has to exist on this host.
  #
  # HERMES_HOME is read from the service module rather than assumed, so the
  # tool reads the same state directory the running agent uses.
  hermesHome = config.services.hermes-agent.hermesHome;
  skillsWorkTree = "/home/codebam/Documents/git/hermes-skills";

  skillsBackup = pkgs.writeShellApplication {
    name = "hermes-skills-backup";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      git
      ffmpeg
    ];
    text = ''
      upstream=${inputs.hermes-agent}
      repo=''${HERMES_SKILLS_REPO:-${skillsWorkTree}}
      push=1
      [ "''${1:-}" = "--no-push" ] && push=0

      [ -d "$repo/.git" ] || { echo "not a git work tree: $repo" >&2; exit 1; }

      # A skill is upstream's if the same category/name exists in either of the
      # two trees hermes ships. Content is deliberately not compared: a shipped
      # skill that merely drifted from a newer upstream rev is not something I
      # wrote, and diffing it in would churn on every hermes-agent bump.
      is_upstream() {
        [ -d "$upstream/skills/$1" ] || [ -d "$upstream/optional-skills/$1" ]
      }

      # $1 = skill tree to read, $2 = destination inside the repo.
      collect() {
        src=$1
        dst=$2
        [ -d "$src" ] || return 0

        for cat in "$src"/*; do
          [ -d "$cat" ] || continue
          cname=$(basename "$cat")
          [ "$cname" = "index-cache" ] && continue

          # A category holding a SKILL.md directly is a skill the agent wrote
          # at the wrong depth (the caveman one is). Keep the layout it has, so
          # a restore is a plain copy back.
          if [ -f "$cat/SKILL.md" ] && ! is_upstream "$cname"; then
            mkdir -p "$dst/$cname"
            cp -f "$cat/SKILL.md" "$dst/$cname/SKILL.md"
          fi

          for skill in "$cat"/*; do
            [ -d "$skill" ] || continue
            sname=$(basename "$skill")
            is_upstream "$cname/$sname" && continue
            mkdir -p "$dst/$cname"
            cp -rT "$skill" "$dst/$cname/$sname"
            echo "  $cname/$sname"
          done
        done
      }

      echo "default profile:"
      collect "${hermesHome}/skills" "$repo/skills"

      for pdir in "${hermesHome}"/profiles/*; do
        [ -d "$pdir/skills" ] || continue
        pname=$(basename "$pdir")
        echo "profile $pname:"
        collect "$pdir/skills" "$repo/profiles/$pname"
      done

      # Copies land read-only when the source was; make them editable again so
      # the work tree behaves like a normal checkout.
      chmod -R u+w "$repo/skills" "$repo/profiles" 2>/dev/null || true

      # Nothing here deletes: a skill removed from HERMES_HOME stays in the
      # repo. That is the point of a backup, and `git rm` is one command away
      # when a removal was deliberate.
      cd "$repo"
      if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
        echo "no changes"
        exit 0
      fi

      git add -A
      git status --short
      git commit -m "backup: hermes-authored skills $(date -u +%Y-%m-%dT%H:%MZ)"

      if [ "$push" = 1 ]; then
        git push
      else
        echo "committed; not pushed (--no-push)"
      fi
    '';
  };
in
{
  # Hermes is per-user now, not the retired system service: the upstream
  # home-manager module installs the package (`programs.hermes-agent` below),
  # exports HERMES_HOME, and writes $HERMES_HOME/.env on every activation from
  # environmentFiles. The file it reads is the sops template built from the
  # individual API-key secrets, so the hand-maintained hermes-env blob does not
  # have to come back.
  #
  # Gated to the desktop like the old module: the template below, the
  # OpenRouter key path, and the Telegram gateway are desktop-only.
  services.hermes-agent = lib.mkIf isDesktop {
    enable = true;
    environmentFiles = [ osConfig.sops.templates."hermes-env".path ];

    # The memory provider (home/hermes-agent-memory.nix) rides the default
    # package directly rather than through the module's `extraPythonPackages`
    # option: that option routes through the module's package override, which
    # also resets extraDependencyGroups to the option default `[]` -- and so
    # REPLACES the `full` default package's group list. The sealed venv then
    # collapses from the full set to `all` and the platform extras go with
    # it: group `messaging` is what ships python-telegram-bot, so the gateway
    # logs "Platform 'Telegram' dependencies missing" at every start and the
    # Telegram platform never loads. Overriding the default package here
    # keeps its groups and still gets the PYTHONPATH + collision-check
    # treatment the option exists for.
    #
    # It ships as an installed package with a
    # `hermes_agent.memory_providers` entry point -- the route upstream
    # documents for out-of-tree providers, and the only one whose name matches
    # `memory.provider` below (a directory plugin is discovered under its
    # `nix-managed-` symlink name). Built with the venv's own interpreter
    # (hermesPackage.python.pkgs, 3.14 at this pin), because nixpkgs drops an
    # extra package built for another family from PYTHONPATH without a word --
    # see the header of home/hermes-agent-memory.nix. It lands in the same
    # venv `hermes` runs from -- CLI, gateway and the desktop's `hermes serve`
    # child alike.
    package = hermesPackage.override {
      extraPythonPackages = [ memoryProvider.package ];
    };

    # agentic-inbox email MCP. The stdio bridge authenticates to the Worker
    # with the `email-api-key` sops secret, falling back to the local
    # Wrangler login token on hosts without it (home/email-mcp.nix); its
    # launcher pins Node and PATH itself so this service does not depend on
    # the interactive shell's profile.
    mcpServers = {
      ${emailMcp.name} = {
        command = emailMcp.runner;
        args = [
          emailMcp.bridge
          "--url"
          emailMcp.url
        ];
      };

      # Google Calendar MCP (home/google-calendar-mcp.nix): the local stdio
      # server from pkgs/google-calendar-mcp.nix, authenticated with the
      # `google-calendar-oauth` sops secret, falling back to the manual
      # credentials copy until the first activation that mounts it. Reads
      # and writes go to Sean's own calendar at his request, so no extra
      # policy text like the email server's.
      ${calendarMcp.name} = {
        command = calendarMcp.launcher;
      };

      # Shared agent-memory knowledge graph (home/agent-memory.nix): a remote
      # Streamable HTTP row onto the one `agent-memory` unit, not a stdio
      # spawn -- the JSONL store takes no cross-process lock, so the single
      # shared writer is the point; Hermes connects like the other harnesses.
      ${agentMemory.name} = {
        inherit (agentMemory) url;
      };
    };

    # The gateway shares this HERMES_HOME. TELEGRAM_BOT_TOKEN turns the
    # Telegram platform on by itself; TELEGRAM_ALLOWED_USERS then pins the
    # only account the bot answers to. The user ID is not a credential, so
    # it goes through `environment` rather than the sops env file.
    #
    # Webhook mode in place of long polling: Telegram pushes updates to the
    # cloudflared hostname (desktop/configuration/cloudflared.nix), which
    # forwards them to the loopback listener, so nothing on the WAN listens
    # and the origin address never appears in DNS. The delivery secret
    # Telegram must echo rides the sops env file with the bot token.
    environment = {
      TELEGRAM_ALLOWED_USERS = "69148517";
      TELEGRAM_WEBHOOK_URL = "https://tg.codebam.ca/telegram";
      TELEGRAM_WEBHOOK_PORT = "8443";
      TELEGRAM_WEBHOOK_HOST = "127.0.0.1";
      # Home channel: the /sethome target for Sean's DM -- where gateway
      # notices, cron deliveries, and bare `telegram` sends land. Seeded from
      # these at gateway start; pinned because a value that lives only in
      # $HERMES_HOME/.env does not survive activation, which regenerates it.
      TELEGRAM_HOME_CHANNEL = "69148517";
      TELEGRAM_HOME_CHANNEL_NAME = "Sean";
    };
    gateway.enable = true;

    # Pin the startup route. home/agents.nix declares the token-plan
    # providers for explicit /model picks; this keeps a mutable `hermes model`
    # selection or an upstream default from silently changing what every turn
    # lands on. The OpenCode Go subscription is the default because both
    # subscriptions sit in the credential pool, so a spent one rotates to the
    # second mid-session. mimo-v2.6-pro is the id the Go relay (a flat
    # namespace, no vendor prefixes) and models.dev both carry for Xiaomi
    # MiMo-V2.6-Pro (multimodal reasoning, 1M context, 131k output). The
    # override below keys off the direct DeepSeek API's deepseek-flash id and
    # stays dormant on this route.
    settings = {
      model = {
        # Empty base_url clears the OpenRouter URL persisted by the previous
        # default so the built-in OpenCode Go endpoint wins.
        base_url = "";
        default = "deepseek/deepseek-v4.1-flash-1017";
        provider = "nano-gpt";
      };
      # Standing operator notes for every session. In this Hermes revision
      # the native MCP client ignores a server's InitializeResult
      # instructions, and `environment_hint` is the only always-on
      # system-prompt surface available through config.yaml. Coding sessions
      # also see the same text through `coding_instructions`. The standing
      # facts and the memory guidance ride the same channel: native memory is
      # off below, so this text is the replacement.
      agent = {
        environment_hint = emailMcp.policy + cfCli.guidance + standingFacts + memoryGuidance;
        coding_instructions = emailMcp.policy + cfCli.guidance + standingFacts + memoryGuidance;
        # Top tier of the Go relay's reasoning_effort knob for the DeepSeek V4
        # family (low/high/max; Hermes' xhigh maps onto max). The main loop on
        # every route asks for max and each route clamps onto the levels it
        # accepts; auxiliary tasks resolve effort from their own
        # auxiliary.<task> entries, so a title or approval call stays cheap.
        reasoning_effort = "max";
      };
      # Web search/extract routing, pinned so the process environment cannot
      # decide it: sessionVariables exports SEARXNG_URL, which would otherwise
      # let each process resolve to whichever backend looks available. Search
      # stays on the local SearXNG instance; extraction runs on the Tavily key
      # from SOPS (desktop/configuration/sops.nix) instead of the anonymous
      # shared keyless tier.
      web = {
        search_backend = "searxng";
        extract_backend = "tavily";
      };
      # Native memory off, deliberately: the always-on facts live in this file
      # (standingFacts above) and durable knowledge in the shared agent-memory
      # graph, whose provider (home/hermes-agent-memory.nix) recalls entries
      # into every turn and asks for a review every ten turns. A Hermes-local
      # MEMORY.md/USER.md would be a third copy that drifts from both, and the
      # provider only ever reads the graph -- writes stay on the
      # mcp__memory__* tools, as for every other harness.
      memory = {
        memory_enabled = false;
        user_profile_enabled = false;
        # Names the entry point the package above installs; from here on the
        # provider, not the native store, fills the per-turn memory block.
        provider = memoryProvider.name;
      };
      # Dormant under the Go default above; it applies if the route moves back
      # to the direct DeepSeek API, whose static catalog knows only the legacy
      # deepseek-v4-flash alias. The Go relay's deepseek-v4.1-flash needs no
      # entry: models.dev carries it with the same metadata (1M context, 384k
      # output, vision, reasoning).
      model_overrides = {
        "deepseek"."deepseek-flash" = {
          context_window = 1000000;
          max_output_tokens = 384000;
          supports_tools = true;
          supports_vision = true;
          supports_reasoning = true;
        };
      };
      # Kept for a switch back to OpenRouter: same Pareto floor as
      # opencode/pi/dsh.
      openrouter.min_coding_score = 0.65;
      # The allowlist above is the whole access policy: do not let unknown DMs
      # fall back into the pairing flow.
      unauthorized_dm_behavior = "ignore";
      terminal = {
        # "." is Hermes' placeholder for the launch directory; the module
        # would otherwise write its workingDirectory default into config.yaml.
        cwd = ".";
      };
    };
  };

  # The installation half of the upstream module (separate from the service
  # since 0.21): `hermes` on PATH with HERMES_HOME exported, and Hermes
  # Desktop with an XDG launcher that carries HERMES_HOME itself, because a
  # .desktop launch reads no shell profile. Desktop-only, like the service
  # block above; the app spawns its own headless `hermes serve` child from the
  # wrapped binary, so the managed config.yaml, the sops-built .env, and the
  # OpenCode Go credential pool are what it runs on. Electron userData (window
  # state, themes, connections) is preserved as .config/Hermes in
  # modules/system/preservation.nix.
  programs.hermes-agent = {
    enable = isDesktop;
    desktop = {
      enable = isDesktop;
      # No `package` here: the default is `programs.hermes-agent.package`'s
      # `hermesDesktop` passthru. The local re-call of upstream's desktop.nix
      # existed only to intercept its pinned Electron headers fetchurl;
      # upstream now uses nixpkgs' own `electron.headers`, so nothing is left
      # to override and the passthru is the supported path.
    };
  };

  # The skills backup tool from the let block: an operator tool, not an agent
  # tool — it reads the agent's skill trees and pushes with this user's git
  # credentials. Desktop-only with the service above, since it backs up the
  # state of a hermes install only this host has.
  home.packages = lib.optionals isDesktop [ skillsBackup ];

  # Seed pm's tool store (home/hermes-pm-facts.nix) on every activation, so a
  # hermes bump re-points the entries at the new store paths. `entryAfter
  # writeBoundary` because it writes into HERMES_HOME, which the module's own
  # activation creates; gated like the service because only this host runs pm.
  home.activation.hermes-pm-facts = lib.mkIf isDesktop pmFacts.script;
}
