{
  osConfig,
  lib,
  ...
}:

let
  isDesktop = osConfig.networking.hostName == "nixos-desktop";
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

    # The gateway shares this HERMES_HOME. TELEGRAM_BOT_TOKEN turns the
    # Telegram platform on by itself; TELEGRAM_ALLOWED_USERS then pins the
    # only account the bot answers to. The user ID is not a credential, so it
    # goes through `environment` rather than the sops env file.
    environment.TELEGRAM_ALLOWED_USERS = "69148517";
    gateway.enable = true;

    # Pin the startup route. home/agents.nix declares the token-plan
    # providers for explicit /model picks; this keeps a mutable `hermes model`
    # selection or an upstream default from silently changing what every turn
    # lands on. The Pareto floor matches the opencode/pi/dsh config in
    # home/agents.nix.
    settings = {
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "openrouter/pareto-code";
        provider = "openrouter";
      };
      openrouter.min_coding_score = 0.65;
      # The allowlist above is the whole access policy: do not let unknown DMs
      # fall back into the pairing flow.
      unauthorized_dm_behavior = "ignore";
      # "." is Hermes' placeholder for the launch directory; the module would
      # otherwise write its workingDirectory default into config.yaml.
      terminal.cwd = ".";
    };
  };
}
