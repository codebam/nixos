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
  # Gated to the desktop like the old module: the template below and the
  # OpenRouter key path are desktop-only.
  services.hermes-agent = lib.mkIf isDesktop {
    enable = true;
    environmentFiles = [ osConfig.sops.templates."hermes-env".path ];

    # Pin the provider and model to the key that exists. Without this a
    # mutable `hermes model` selection or an upstream default can point the
    # agent at a provider it has no credential for. The Pareto floor matches
    # the opencode/pi/dsh config in home/agents.nix.
    settings = {
      model = {
        base_url = "https://openrouter.ai/api/v1";
        default = "openrouter/pareto-code";
        provider = "openrouter";
      };
      openrouter.min_coding_score = 0.65;
      # "." is Hermes' placeholder for the launch directory; the module would
      # otherwise write its workingDirectory default into config.yaml.
      terminal.cwd = ".";
    };
  };
}
