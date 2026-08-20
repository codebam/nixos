{ config, ... }:

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

    # Same reasoning as ollama's own host setting in ./services.nix: the proxy
    # has no authentication (no master_key below), and tailscale0 and virbr0
    # are trusted interfaces, so anything but loopback hands the OpenRouter key
    # -- as a spend-anything completions endpoint -- to the tailnet.
    host = "127.0.0.1";
    port = 4000;

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
