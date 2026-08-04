{ config, pkgs, inputs, ... }:

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
        default = "deepseek/deepseek-v4-flash";
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

  # Add hermes desktop app as a home-manager package for codebam
  home-manager.users.codebam = { pkgs, ... }: {
    home.packages = with pkgs; [
      inputs.hermes-agent.packages.${system}.desktop
    ];
  };
}
