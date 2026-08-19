{
  pkgs,
  lib,
  ...
}:

let
  # Both harnesses read OPENROUTER_API_KEY from the environment. The key
  # already exists on this host inside the `hermes-env` sops secret, so it is
  # mounted a second time as `opencode-env` (same yaml key, owned by codebam)
  # rather than duplicated in secrets.yaml — one key, one place to rotate it.
  #
  # Only OPENROUTER_API_KEY is lifted out: hermes-env also carries chat-gateway
  # tokens that have no business in an interactive shell's environment.
  loadKey = pkgs.writeShellScript "openrouter-load-key" ''
    secret=/run/secrets/opencode-env
    if [ -r "$secret" ]; then
      key=$(${pkgs.gnused}/bin/sed -n 's/^OPENROUTER_API_KEY=//p' "$secret" | tr -d '"' | head -n1)
      [ -n "$key" ] && export OPENROUTER_API_KEY="$key"
    fi
  '';

  # Priced at $1.4/$4.4 per Mtok with a 1M context window. The cheap model
  # handles titles, summaries, and other background turns.
  codingModel = "z-ai/glm-5.3";
  cheapModel = "minimax/minimax-m3";

  opencode = pkgs.symlinkJoin {
    name = "opencode-wrapped-${pkgs.opencode.version}";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode --run '. ${loadKey}'
    '';
  };

  # Pi ships its own updater and an install/version ping, neither of which
  # applies to a /nix/store copy it cannot write to.
  pi = pkgs.symlinkJoin {
    name = "pi-coding-agent-wrapped-${pkgs.pi-coding-agent.version}";
    paths = [ pkgs.pi-coding-agent ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/pi \
        --run '. ${loadKey}' \
        --set PI_SKIP_VERSION_CHECK 1 \
        --set PI_TELEMETRY 0
    '';
  };
  piSettings = {
    defaultProvider = "openrouter";
    defaultModel = codingModel;
    enableInstallTelemetry = false;
  };

  # Nix keys win over whatever pi last wrote, and a settings.json that pi (or a
  # half-finished edit) left unparseable is rebuilt rather than aborting
  # activation.
  piSettingsMerge = pkgs.writeShellScript "pi-settings-merge" ''
    set -eu
    settings="$HOME/.pi/agent/settings.json"
    mkdir -p "$(dirname "$settings")"
    current=$(${pkgs.jq}/bin/jq . "$settings" 2>/dev/null || echo '{}')
    printf '%s' "$current" \
      | ${pkgs.jq}/bin/jq --argjson managed ${lib.escapeShellArg (builtins.toJSON piSettings)} '. * $managed' \
      > "$settings.tmp"
    mv "$settings.tmp" "$settings"
  '';
in
{
  home.packages = [
    opencode
    pi
  ];

  # Written from nix rather than left to `opencode` itself: the TUI's model
  # picker persists into this same file, and a hand-picked model would
  # otherwise outlive the choice made here.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "openrouter/${codingModel}";
    small_model = "openrouter/${cheapModel}";
  };

  # Pi's settings.json is mutable state — `/settings` and the model picker
  # write to it — so it cannot be a read-only store symlink like opencode's
  # config. Merge instead, nix keys winning, the same way the hermes module
  # handles its own config.yaml.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${piSettingsMerge}
  '';
}
