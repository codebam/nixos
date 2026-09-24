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
      # also see the same text through `coding_instructions`.
      agent = {
        environment_hint = emailMcp.policy + sandboxPolicy;
        coding_instructions = emailMcp.policy + sandboxPolicy;
        # Top tier of the Go relay's reasoning_effort knob for the DeepSeek V4
        # family (low/high/max; Hermes' xhigh maps onto max). The main loop on
        # every route asks for max and each route clamps onto the levels it
        # accepts; auxiliary tasks resolve effort from their own
        # auxiliary.<task> entries, so a title or approval call stays cheap.
        reasoning_effort = "max";
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
