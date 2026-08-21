{
  config,
  pkgs,
  lib,
  ...
}:

let
  # litellm 1.97.0's proxy imports `expression` (a functional-programming
  # library) from its MCP outbound-credentials module, and any ImportError in
  # that chain is rethrown as a fatal "Missing dependency ... Run pip install
  # litellm[proxy]" -- so the proxy will not start without it. nixpkgs does not
  # package it, and the litellm derivation does not list it, so it is built
  # here and appended to the dependency list.
  #
  # Pure python, wheel-installed to skip the build backend. Drop this once
  # nixpkgs carries python3Packages.expression and litellm depends on it.
  expression = pkgs.python3Packages.buildPythonPackage rec {
    pname = "expression";
    version = "5.7.0";
    format = "wheel";
    src = pkgs.python3Packages.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-2NkDy53cslLb1kYS4ym9hvCddwx4Eur4+cwLn45kgL0=";
    };
    propagatedBuildInputs = [ pkgs.python3Packages.typing-extensions ];
    doCheck = false;
  };
in
{
  # A loopback gateway that puts the local qwen3.8 in front of the same model
  # on OpenRouter, so a session starts on the card and only leaves the machine
  # when it no longer fits there.
  #
  # This lives here rather than in opencode's own config because opencode has
  # no notion of a fallback model: its config takes one `model`, and no plugin
  # hook can swap the model mid-session (`chat.params` receives it read-only).
  # The switch therefore has to happen below the harness, at the endpoint.
  #
  # Both deployments are qwen3.8 27B -- the local q4_0 GGUF and OpenRouter's
  # copy -- so a conversation that crosses over keeps the same model's
  # behaviour, just with a bigger window and a bill.
  services.litellm = {
    enable = true;
    package = pkgs.litellm.overridePythonAttrs (old: {
      dependencies = (old.dependencies or [ ]) ++ [ expression ];

      # The other half of making the fallback fire. litellm's pre-call context
      # check calls get_router_model_info, which looks the deployment up in the
      # model cost map *before* it reads the `model_info` written in the config
      # -- and an unmapped model raises there, inside a try/except that logs and
      # moves on. The effect is that the local deployment is never filtered, the
      # oversized prompt goes to ollama anyway, and ollama silently truncates it
      # (measured: a ~200k-token prompt came back as 81922 prompt_tokens, served
      # by ollama, with x-litellm-attempted-fallbacks: 0).
      #
      # Nothing in the config format can prepay that lookup -- `base_model` is
      # only consulted for azure -- so the entry is added to the map itself.
      postInstall = (old.postInstall or "") + ''
        for f in $out/${pkgs.python3.sitePackages}/litellm/model_prices_and_context_window_backup.json; do
          ${lib.getExe pkgs.jq} '. + {
            "ollama_chat/qwen3.8:160k": {
              litellm_provider: "ollama_chat",
              mode: "chat",
              max_tokens: 163840,
              max_input_tokens: 163840,
              max_output_tokens: 32000,
              input_cost_per_token: 0.0,
              output_cost_per_token: 0.0,
              supports_function_calling: true
            }
          }' "$f" > "$f.new"
          mv "$f.new" "$f"
        done
      '';
    });

    # Same reasoning as ollama's own host setting in ./services.nix: the proxy
    # has no authentication (no master_key below), and tailscale0 and virbr0
    # are trusted interfaces, so anything but loopback hands the OpenRouter key
    # -- as a spend-anything completions endpoint -- to the tailnet.
    host = "127.0.0.1";
    port = 4000;

    # Forces the packaged cost map -- the one patched above -- instead of the
    # copy litellm fetches from GitHub at every startup, which would otherwise
    # overwrite the qwen3.8 entry the pre-call check depends on. Also means
    # startup needs no network. The module's own defaults are repeated because
    # setting this option replaces them.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
      LITELLM_LOCAL_MODEL_COST_MAP = "True";
    };

    # OPENROUTER_API_KEY. systemd reads EnvironmentFile as root before the unit
    # drops to its DynamicUser, so the secret can stay root-owned 0400 and no
    # static litellm user is needed.
    environmentFile = config.sops.secrets.litellm-env.path;

    settings = {
      model_list = [
        {
          # The :160k tag, not :latest -- see the measured context/VRAM table
          # in ./services.nix for why 160k is the ceiling on this card.
          model_name = "qwen3.8";
          litellm_params = {
            model = "ollama_chat/qwen3.8:160k";
            api_base = "http://127.0.0.1:11434";
          };
          # What `enable_pre_call_checks` compares the prompt against. Held
          # under the model's real 163840 so there is room for the reply, and
          # because ollama does not error on an oversized prompt -- it
          # silently drops the front of it, which would look like the model
          # going senile rather than like a fallback that never fired.
          model_info = {
            max_input_tokens = 145000;
            max_output_tokens = 32000;
          };
        }
        {
          model_name = "qwen3.8-cloud";
          litellm_params = {
            model = "openrouter/qwen/qwen3.8-27b";
            api_key = "os.environ/OPENROUTER_API_KEY";
          };
          # OpenRouter advertises 1M for this model. $0.45/$3.20 per Mtok.
          model_info = {
            max_input_tokens = 1000000;
            max_output_tokens = 32000;
          };
        }
      ];

      router_settings = {
        # The pair that does the actual work: pre-call checks token-count the
        # request against max_input_tokens above and rule the local deployment
        # out when it no longer fits, which raises ContextWindowExceededError,
        # which context_window_fallbacks turns into a retry on the cloud copy.
        # Without the pre-call check there is nothing to fall back *from*,
        # since ollama answers a too-long prompt instead of refusing it.
        enable_pre_call_checks = true;
        context_window_fallbacks = [ { "qwen3.8" = [ "qwen3.8-cloud" ]; } ];

        # The plain fallback covers the other way the local model goes away:
        # ollama stopped, GPU wedged, model still loading. Same destination,
        # so a session survives it rather than erroring in the TUI.
        fallbacks = [ { "qwen3.8" = [ "qwen3.8-cloud" ]; } ];
      };

      # Harnesses send sampling params the local runner does not know; drop
      # them instead of failing the call.
      litellm_settings.drop_params = true;
    };
  };
}
