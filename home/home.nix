{ pkgs, inputs, ... }:

{
  home = {
    username = "codebam";
    homeDirectory = "/home/codebam";

    shell = {
      enableShellIntegration = true;
    };

    pointerCursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata Modern Classic";
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Bibata Modern Classic";
      };
      gtk.enable = true;
    };

    shellAliases = { };

    sessionVariables = {
      EDITOR = "hx";
      NIXOS_OZONE_WL = "1";
      OBS_VKCAPTURE = "1";
      # WLR_RENDERER = "vulkan";
      MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
      PROTON_ENABLE_WAYLAND = "1";
      PROTON_ENABLE_HDR = "1";
      PROTON_USE_NTSYNC = "1";
      SEARXNG_API_URL = "http://localhost:8081";
    };

    packages = with pkgs; [
      (pkgs.writeShellScriptBin "hxg" ''
        set -euo pipefail
        if [[ $# -eq 0 ]]; then
          echo "Usage: $(basename "$0") <pattern>"
          echo "Searches for a pattern and opens ALL matches in Helix."
          exit 1
        fi
        ${pkgs.ripgrep}/bin/rg --vimgrep "$1" | cut -d ':' -f 1-3 | xargs --no-run-if-empty hx
      '')
      (writeShellScriptBin "trace" ''
        ${curl}/bin/curl https://www.cloudflare.com/cdn-cgi/trace
      '')
      (writeShellScriptBin "sway-kill-parent-fzf" ''
        set -euo pipefail
        WINDOW_LIST=$(${pkgs.sway}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.pid? and .name) | "\(.pid) | \(.app_id // .window_properties.class // .name)"')
        if [ -z "$WINDOW_LIST" ]; then
          echo "No selectable windows found." >&2
          exit 0
        fi
        CHOSEN_WINDOW=$(echo "$WINDOW_LIST" | ${pkgs.fzf}/bin/fzf --prompt="Kill Parent Of> " --height=40% --layout=reverse --border)
        if [ -z "$CHOSEN_WINDOW" ]; then
            echo "Operation cancelled."
            exit 0
        fi
        PID=$(echo "$CHOSEN_WINDOW" | cut -d'|' -f1 | tr -d ' ')
        PPID=$(ps -o ppid= -p "$PID" || true) # Use '|| true' to prevent exit on error if PID vanishes
        if [ -z "$PPID" ]; then
            echo "Error: Could not find parent process for PID $PID." >&2
            exit 1
        fi
        kill "$PPID"
        echo "Sent kill signal to parent process with PID $PPID."
      '')
      (writeShellScriptBin "sretry" ''
        until "$@"; do sleep 1; done
      '')
      (writeShellScriptBin "spaste" ''
        ${curl}/bin/curl -X POST --data-binary @- https://p.seanbehan.ca
      '')
      (pass.withExtensions (
        subpkgs: with subpkgs; [
          pass-otp
          pass-genphrase
        ]
      ))
      (discord.override {
        withOpenASAR = true;
        withVencord = true;
      })
      bat
      element-desktop
      gemini-cli
      google-cloud-sdk
      grim
      heroic
      nil
      nixd
      nodePackages_latest.nodejs
      opentofu
      pavucontrol
      playerctl
      rcm
      ripgrep
      slurp
      telegram-desktop
      tor-browser
      weechat
      youtube-music
      kdePackages.kdenlive
    ];

    file.".config/helix/helix.scm".text = ''
      (require "helix/editor.scm")
      (require (prefix-in helix. "helix/commands.scm"))
      (require "helix-file-watcher/file-watcher.scm")
      (require "helix-discord-rpc/helix-discord-rpc.scm")

      (provide discord-rpc)

      ;;@doc
      ;; Discord RPC plugin
      (define (discord-rpc)
        (discord-rpc-connect))

      (provide file-watcher)

      ;;@doc
      ;; File watcher plugin
      (define (file-watcher)
        (spawn-watcher))
      
      (provide hello-world)
      
      ;;@doc
      ;; Prints "Hello, World!" to the status line
      (define (hello-world)
        (helix.echo "Hello, World!"))
    '';

    file.".config/helix/init.scm".text = ''
      (require-builtin steel/random as rand::)
      (require (prefix-in helix. "helix/commands.scm"))
      (require (prefix-in helix.static. "helix/static.scm"))
      (require "scooter/scooter.scm")
      
      ;; Picking one from the possible themes
      ; (define possible-themes '("ayu_mirage" "tokyonight_storm" "catppuccin_macchiato"))
      
      ; (define (select-random lst)
      ;   (let ([index (rand::rng->gen-range 0 (length lst))]) (list-ref lst index)))
      
      ; (define (randomly-pick-theme options)
      ;   ;; Randomly select the theme from the possible themes list
      ;   (helix.theme (select-random options)))
      
      ; (randomly-pick-theme possible-themes)
    '';

    file.".gitignore".text = ''
      Session.vim
      .claude/
      .gemini/
    '';

    stateVersion = "25.11";
  };
}
