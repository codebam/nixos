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

  # Hermes Desktop from the pinned hermes-agent input, re-called here for one
  # reason: upstream's desktop.nix fetches Electron's Node headers from a URL
  # pinned to the hash of the Electron version in the input's own flake.lock
  # (41.10.3). The input follows this flake's nixpkgs, whose Electron has moved
  # on, so that fetch can never match again and the desktop build would fail on
  # it. Everything else stays upstream's build; only the `pkgs` scope that one
  # fetchurl resolves in is wrapped, and the call is answered with nixpkgs' own
  # headers for the Electron actually shipped, repacked into the tarball shape
  # the build unpacks (a `node_headers/` root that its `tar
  # --strip-components=1` removes again). Revisit on a hermes-agent bump: drop
  # this and use `...packages.${system}.desktop` again if upstream stops
  # pinning the hash or pins one for the nixpkgs Electron in use.
  hermesAgent = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
  # home-manager module installs the package, exports HERMES_HOME, and writes
  # $HERMES_HOME/.env on every activation from environmentFiles. The file it
  # reads is the sops template built from the individual API-key secrets, so
  # the hand-maintained hermes-env blob does not have to come back.
  #
  # Gated to the desktop like the old module: the template below, the
  # OpenRouter key path, and the Telegram gateway are desktop-only.
  services.hermes-agent = lib.mkIf isDesktop {
    enable = true;
    environmentFiles = [ osConfig.sops.templates."hermes-env".path ];

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
    # lands on. deepseek-flash is the direct DeepSeek API's current model name
    # for DeepSeek-V4.1-Flash.
    settings = {
      model = {
        # Empty base_url clears the OpenRouter URL persisted by the previous
        # default so the built-in deepseek endpoint wins.
        base_url = "";
        default = "deepseek-flash";
        provider = "deepseek";
      };
      # Standing operator policy for outbound email. In this Hermes
      # revision the native MCP client ignores a server's InitializeResult
      # instructions, and `environment_hint` is the only always-on
      # system-prompt surface available through config.yaml. Coding
      # sessions also see the same rule through `coding_instructions`.
      agent = {
        environment_hint = emailMcp.policy;
        coding_instructions = emailMcp.policy;
      };
      # Hermes' static DeepSeek catalog only knows the legacy
      # deepseek-v4-flash alias, so pin the metadata DeepSeek documents for
      # the current deepseek-flash id.
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
    };
  };

  # Hermes Desktop, the upstream Electron app from the same flake input the
  # agent module comes from (see the let block for the one Electron-headers
  # adjustment). It shares $HERMES_HOME with the CLI and gateway: the upstream
  # wrapper points HERMES_DESKTOP_HERMES at the fully wrapped `hermes` binary
  # and the app spawns its own headless `hermes serve` child, so the managed
  # config.yaml, the sops-built .env, and the OpenCode Go credential pool are
  # what it runs on. A .desktop launch inherits no shell environment, which is
  # fine here: everything it needs is in HERMES_HOME. Electron userData
  # (window state, themes, connections) is preserved as .config/Hermes in
  # modules/system/preservation.nix.
  home.packages = lib.mkIf isDesktop [ hermesDesktop ];
}
