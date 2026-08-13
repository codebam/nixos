{
  pkgs,
  config,
  ...
}:

let
  # Pinned to commits, not branch names. With a branch name the hash is the only
  # thing holding the content still, so the first upstream push turns every
  # fresh build into a hash mismatch -- which is exactly what had happened to
  # reshade-shaders' `slim` branch, so this also un-breaks uncached builds.
  sweetfx-src = pkgs.fetchFromGitHub {
    owner = "CeeJayDK";
    repo = "SweetFX";
    rev = "16d1a42247cb5baaf660120ee35c9a33bb94649c";
    hash = "sha256-h7nqn4aQHomrI/NG0Oj2R9bBT8VfzRGVSZ/CSi/Ishs=";
  };
  reshade-headers = pkgs.fetchFromGitHub {
    owner = "crosire";
    repo = "reshade-shaders";
    rev = "6db142b4b1a05c764222e5b0bd9a644b7ccfe1dc";
    hash = "sha256-WqT4eU8ZlGwKEgUEGlivz+35GprKX4goBeLnp9D5lTY=";
  };
  reshade-shaders = pkgs.symlinkJoin {
    name = "reshade-shaders";
    paths = [
      "${sweetfx-src}/Shaders"
      "${reshade-headers}/Shaders"
    ];
  };
in
{
  home = {
    username = "codebam";
    homeDirectory = "/home/codebam";

    sessionPath = [
      "${config.home.homeDirectory}/.npm-global/bin"
      "${config.home.homeDirectory}/.kimi-code/bin"
    ];

    shell = {
      enableShellIntegration = true;
    };

    pointerCursor.enable = true;

    shellAliases = { };

    sessionVariables = {
      EDITOR = "hx";
      NIXOS_OZONE_WL = "1";
      WLR_RENDERER = "vulkan";
      GTK_USE_PORTAL = "1";
      SEARXNG_API_URL = "http://localhost:8081";
      _JAVA_AWT_WM_NONREPARENTING = "1";
    };

    packages = with pkgs; [
      (pkgs.writeShellScriptBin "vim" ''
        hx $@
      '')
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
        WINDOW_LIST=$(${config.wayland.windowManager.sway.package}/bin/swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r '.. | select(.pid? and .name) | "\(.pid) | \(.app_id // .window_properties.class // .name)"')
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
        # Not PPID: bash marks that one readonly, so assigning to it aborts the
        # script under `set -e` before anything is killed.
        parent_pid=$(${pkgs.procps}/bin/ps -o ppid= -p "$PID" | tr -d ' ' || true)
        if [ -z "$parent_pid" ]; then
            echo "Error: Could not find parent process for PID $PID." >&2
            exit 1
        fi
        kill "$parent_pid"
        echo "Sent kill signal to parent process with PID $parent_pid."
      '')
      (writeShellScriptBin "sretry" ''
        until "$@"; do sleep 1; done
      '')
      (writeShellScriptBin "spaste" ''
        ${curl}/bin/curl -X POST --data-binary @- https://pastebin.codebam.ca
      '')

      bat
      claude-code
      dust
      # Both are bound to tmux popups in home/shell-common.nix by store path;
      # on PATH as well so they are usable outside tmux.
      sesh
      lazygit
      nvtopPackages.amd
      antigravity-cli
      google-cloud-sdk
      arrpc
      grim
      nil
      nixfmt
      nixd
      nodejs_latest
      opentofu
      pwvucontrol
      playerctl
      rcm
      ripgrep
      slurp
      jq
      supersonic
      weechat
      calcurse
      high-tide
      feishin
      cinny-desktop
      (pkgs.python3.withPackages (
        python-pkgs: with python-pkgs; [
          virtualenv
          tkinter
          pip
          requests
        ]
      ))
      (pkgs.writeShellScriptBin "agy-sandbox" ''
        mkdir -p "$HOME/.config/agy-sandbox"

        # 2. Execute the sandbox wrapper
        exec ${pkgs.bubblewrap}/bin/bwrap \
          --ro-bind /nix/store /nix/store \
          --proc /proc \
          --dev /dev \
          --ro-bind /sys /sys \
          --ro-bind /etc /etc \
          --ro-bind /etc/ssl/certs /etc/ssl/certs \
          --ro-bind /run/systemd/resolve /run/systemd/resolve \
          --share-net \
          --bind "$HOME/.config/agy-sandbox" "$HOME" \
          --bind "$(pwd)" "$(pwd)" \
          --uid "$(id -u)" \
          --gid "$(id -g)" \
          $(readlink -f $(which agy)) "$@"
      '')
    ];

    file = {
      ".config/helix/init.scm".text = ''
        (require-builtin steel/random as rand::)
        (require (prefix-in helix. "helix/commands.scm"))
        (require (prefix-in helix.static. "helix/static.scm"))
        (require "helix/configuration.scm")
        (define-lsp "steel-language-server" (command "steel-language-server") (args '()))
        (define-language "scheme"
                         (language-servers '("steel-language-server")))
        (require "helix-copilot/copilot.scm")
        (set-copilot-model! "qwen3-coder")
      '';

      ".config/helix/helix.scm".text = ''
        (require "helix/editor.scm")
        (require (prefix-in helix. "helix/commands.scm"))
        (require "helix-file-watcher/file-watcher.scm")

        (provide file-watcher)
        ;;@doc
        ;; File watcher plugin
        (define (file-watcher)
          (spawn-watcher))
      '';

      ".gitignore".text = ''
        Session.vim
        .claude/
      '';
    };

    stateVersion = "26.05";
  };

  xdg = {
    configFile = {
      "vkBasalt/vkBasalt.conf".text = ''
        reshadeIncludePath = ${reshade-shaders}
        reshadeTexturePath = ${sweetfx-src}/Textures
        effects = vibrance:cas
        vibrance = ${reshade-shaders}/SweetFX/Vibrance.fx
        Vibrance = 0.25
        casSharpness = 0.35
      '';
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
