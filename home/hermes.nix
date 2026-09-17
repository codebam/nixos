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
}
