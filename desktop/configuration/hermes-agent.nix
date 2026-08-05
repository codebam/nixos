{
  config,
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    # Match the current session's model/provider
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
    };
  };

  # addToSystemPackages exports HERMES_HOME=/var/lib/hermes/.hermes system-wide.
  # That tree is 2770/0640 hermes:hermes, so interactive users need the group.
  users.users.codebam.extraGroups = [ "hermes" ];

  # Add hermes desktop app as a home-manager package for codebam
  home-manager.users.codebam = { pkgs, ... }: {
    home.packages = with pkgs; [
      inputs.hermes-agent.packages.${system}.desktop
    ];
  };
}
