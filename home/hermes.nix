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

  # The OpenSandbox terminal backend plugin (home/hermes-opensandbox.nix):
  # terminal and file commands run in workspace containers instead of the host
  # shell, the same tier as opencode2's shell and dsh's default world.
  opensandboxPlugin = import ./hermes-opensandbox.nix { inherit config pkgs lib; };

  # Always-on system-prompt note about that sandbox. Same channel and reason
  # as the email policy above: it carries the boundary so the agent does not
  # chase resources the container cannot reach, and names the human's escape
  # hatch. Prefixed with two newlines to start its own paragraph.
  sandboxPolicy = "\n\n" + ''
    Terminal and file commands run inside an OpenSandbox container bound to
    the session workspace: the workspace is bind-mounted read-write at its
    host path, /nix/store read-only, and the container has no Nix daemon, no
    credentials, and an ephemeral /root. Host paths outside the workspace do
    not exist in the container; a build that needs its own store goes through
    osb-work. HERMES_NO_SANDBOX=1 in the launching environment restores the
    host shell for that process.
  '';

  # The shared agent-memory knowledge graph (home/agent-memory.nix): the same
  # remote server opencode, dsh, and pi read and write, plus the guidance
  # block those harnesses render -- Hermes registers the
  # `mcp__<server>__<tool>` form like dsh.
  agentMemory = import ./agent-memory.nix;
  memoryGuidance = "\n\n" + agentMemory.guidanceMcp;

  # Standing facts for every Hermes session. Native memory is switched off in
  # the service settings below, so this block -- carried through
  # agent.environment_hint / agent.coding_instructions, the only always-on
  # system-prompt surfaces in this revision -- takes over the role
  # MEMORY.md/USER.md played. Repo state on purpose: reviewed, versioned,
  # identical in every session, never written at runtime. Durable knowledge
  # the user asks Hermes to keep goes to the shared agent-memory graph
  # instead; to change a standing fact, edit this file.
  standingFacts = "\n\n" + ''
    ## Standing facts

    Hermes runs with native memory disabled: there is no MEMORY.md/USER.md and
    no memory tool. This block is the always-on layer, maintained in
    /persistent/etc/nixos/home/hermes.nix; durable facts go to the shared
    agent-memory knowledge graph (see the Agent memory section below), not to
    any Hermes-local file.

    Environment:
    - Hermes config is declarative: `~/.hermes/config.yaml` is GENERATED from
      `/persistent/etc/nixos/home/hermes.nix` (HERMES_MANAGED=home-manager);
      never hand-edit it -- Hermes changes go in that repo. The terminal
      backend "opensandbox" lives in `home/hermes-opensandbox.nix` and
      `home/opensandbox-exec.nix`.
    - Sean's shell is nushell (nu 0.115, reedline, edit_mode=emacs). He does
      NOT use fish, even though `$SHELL` points at fish and a legacy
      `~/.config/fish/config.fish` exists -- never infer the shell from
      `$SHELL`. `config.nu` sources atuin (Ctrl-R + up-arrow), fzf (Alt-C,
      Ctrl-T), carapace, zoxide, starship. bash 5.3 for scripts. His AGENTS.md
      forbids `nix profile install` / `nix-env -i`; ephemeral tools go through
      `nix shell nixpkgs#<pkg> -c`.
    - dsh (@deepseek-ai, the DeepSeek Harness) is his coding agent: `~/.dsh`
      holds profiles, settings.yaml, and session logs as zstd-compressed
      JSONL at `~/.dsh/sessions/<project-dir>/<session-id>/session.v3.jsonl.zstd`
      (event types: session, user/message with source.kind=="user",
      assistant/message, tool/call, tool/result with isError).
    - Local services: SearXNG at 127.0.0.1:8081, the shared agent-memory MCP
      at 127.0.0.1:7979, the OpenSandbox server at 127.0.0.1:8090 (osb-work).
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

  # Hermes Desktop from the pinned hermes-agent input, re-called here for one
  # reason: upstream's desktop.nix fetches Electron's Node headers from a URL
  # pinned to the hash of the Electron version in the input's own flake.lock
  # (41.10.3). The input follows this flake's nixpkgs, whose Electron has moved
  # on, so that fetch can never match again and the desktop build would fail on
  # it. Everything else stays upstream's build; only the `pkgs` scope that one
  # fetchurl resolves in is wrapped, and the call is answered with nixpkgs' own
  # headers for the Electron actually shipped, repacked into the tarball shape
  # the build unpacks (a `node_headers/` root that its `tar
  # --strip-components=1` removes again). The module wraps the result with the
  # launcher environment, so it must keep upstream's `override` arguments
  # (`extraEnv`, `extraRun`). Revisit on a hermes-agent bump: drop this and use
  # the module's default desktop package if upstream stops pinning the hash.
  hermesAgent = config.programs.hermes-agent.package;
  electronHeaders =
    pkgs.runCommand "node-v${pkgs.electron.version}-headers.tar.gz"
      {
        nativeBuildInputs = [
          pkgs.gzip
          pkgs.gnutar
        ];
      }
      ''
        mkdir -p unpacked/node_headers
        cp -r ${pkgs.electron.headers}/. unpacked/node_headers/
        tar -czf $out -C unpacked node_headers
      '';
  hermesDesktop = pkgs.callPackage "${inputs.hermes-agent}/nix/desktop.nix" {
    inherit (hermesAgent) hermesNpmLib;
    inherit hermesAgent;
    pkgs = pkgs // {
      fetchurl =
        args:
        if lib.hasPrefix "https://artifacts.electronjs.org/headers/" (args.url or "") then
          electronHeaders
        else
          pkgs.fetchurl args;
    };
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

    # The OpenSandbox terminal backend above. Activation symlinks the plugin
    # in as nix-managed-<name>; `terminal.backend` and `plugins.enabled` in
    # settings pick it up.
    extraPlugins = [ opensandboxPlugin ];

    # agentic-inbox email MCP. The stdio bridge authenticates to the Worker
    # with the local Wrangler login token (home/email-mcp.nix); its launcher
    # pins Node and PATH itself so this service does not depend on the
    # interactive shell's profile.
    mcpServers = {
      ${emailMcp.name} = {
        command = emailMcp.runner;
        args = [
          emailMcp.bridge
          "--url"
          emailMcp.url
        ];
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
    # only account the bot answers to. The user ID is not a credential, so it
    # goes through `environment` rather than the sops env file.
    environment.TELEGRAM_ALLOWED_USERS = "69148517";
    gateway.enable = true;

    # Pin the startup route. home/agents.nix declares the token-plan
    # providers for explicit /model picks; this keeps a mutable `hermes model`
    # selection or an upstream default from silently changing what every turn
    # lands on. The OpenCode Go subscription is the default because both
    # subscriptions sit in the credential pool, so a spent one rotates to the
    # second mid-session; deepseek-v4.1-flash is the id the Go relay (a flat
    # namespace, no vendor prefixes) and models.dev both carry for
    # DeepSeek-V4.1-Flash. The direct DeepSeek API calls the same model
    # deepseek-flash, which is why the override below still keys off that id.
    settings = {
      model = {
        # Empty base_url clears the OpenRouter URL persisted by the previous
        # default so the built-in OpenCode Go endpoint wins.
        base_url = "";
        default = "deepseek-v4.1-flash";
        provider = "opencode-go";
      };
      # Standing operator notes for every session. In this Hermes revision
      # the native MCP client ignores a server's InitializeResult
      # instructions, and `environment_hint` is the only always-on
      # system-prompt surface available through config.yaml. Coding sessions
      # also see the same text through `coding_instructions`. The standing
      # facts and the memory guidance ride the same channel: native memory is
      # off below, so this text is the replacement.
      agent = {
        environment_hint = emailMcp.policy + sandboxPolicy + standingFacts + memoryGuidance;
        coding_instructions = emailMcp.policy + sandboxPolicy + standingFacts + memoryGuidance;
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
      # graph; a Hermes-local MEMORY.md/USER.md would be a third copy that
      # drifts from both.
      memory = {
        memory_enabled = false;
        user_profile_enabled = false;
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
      # "." is Hermes' placeholder for the launch directory; the module would
      # otherwise write its workingDirectory default into config.yaml.
      terminal.cwd = ".";
      # Terminal and file commands run in OpenSandbox workspace containers
      # (extraPlugins above, home/hermes-opensandbox.nix); the manifest name
      # gates the plugin in.
      terminal.backend = "opensandbox";
      plugins.enabled = [ "opensandbox" ];
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
      # The default follows `programs.hermes-agent.package`; this flake builds
      # it itself instead, see the let block.
      package = hermesDesktop;
    };
  };
}
