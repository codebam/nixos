{ pkgs, inputs, ... }:

let
  sweetfx-src = pkgs.fetchFromGitHub {
    owner = "CeeJayDK";
    repo = "SweetFX";
    rev = "master";
    hash = "sha256-h7nqn4aQHomrI/NG0Oj2R9bBT8VfzRGVSZ/CSi/Ishs=";
  };
  reshade-headers = pkgs.fetchFromGitHub {
    owner = "crosire";
    repo = "reshade-shaders";
    rev = "slim";
    hash = "sha256-87Z+4p4Sx5FcTIvh9cMcHvjySWg5ohHAwvNV6RbLq4A=";
  };
  reshade-shaders = pkgs.symlinkJoin {
    name = "reshade-shaders";
    paths = [
      "${sweetfx-src}/Shaders"
      "${reshade-headers}/Shaders"
    ];
  };
in {
  home = {
    username = "codebam";
    homeDirectory = "/home/codebam";

    shell = {
      enableShellIntegration = true;
    };

    # pointerCursor = {
    #   package = pkgs.bibata-cursors;
    #   name = "Bibata Modern Classic";
    #   size = 24;
    #   x11 = {
    #     enable = true;
    #     defaultCursor = "Bibata Modern Classic";
    #   };
    #   gtk.enable = true;
    # };

    shellAliases = { };

    sessionVariables = {
      EDITOR = "hx";
      NIXOS_OZONE_WL = "1";
      # OBS_VKCAPTURE = "1";
      WLR_RENDERER = "vulkan";
      # AMD_USERQ = "1";
      # RADV_PERFTEST = "userq";
      # GTK_USE_PORTAL = "1";
      # WLR_DRM_NO_ATOMIC = "1"; # screen tearing support
      # MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
      # PROTON_ENABLE_WAYLAND = "1";
      # PROTON_ENABLE_HDR = "1";
      # PROTON_USE_NTSYNC = "1";
      SEARXNG_API_URL = "http://localhost:8081";
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
      (discord-canary.override {
        withOpenASAR = true;
      })
      (discord-ptb.override {
        withOpenASAR = true;
      })
      (discord.override {
        withOpenASAR = true;
      })
      bat
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
      # telegram-desktop
      # tor-browser
      weechat
      pear-desktop
      # kdePackages.kdenlive
      calcurse
      inputs.bsav.packages.${pkgs.stdenv.hostPlatform.system}.default
      (pkgs.python3.withPackages (python-pkgs: with python-pkgs; [
        virtualenv
        tkinter
        pip
        requests
      ]))
    ];

    file.".config/helix/init.scm".text = ''
      (require-builtin steel/random as rand::)
      (require (prefix-in helix. "helix/commands.scm"))
      (require (prefix-in helix.static. "helix/static.scm"))
      (require "helix/configuration.scm")
      (define-lsp "steel-language-server" (command "steel-language-server") (args '()))
      (define-language "scheme"
                       (language-servers '("steel-language-server")))
      (require "scooter/scooter.scm")
      (require "helixwiki/main.scm")
      (wiki-set-path! "~/Documents/wiki")
      (require "colors-steel/main.scm")
    '';

    file.".config/helix/helix.scm".text = ''
      (require "helix/editor.scm")
      (require (prefix-in helix. "helix/commands.scm"))
      (require "helix-file-watcher/file-watcher.scm")

      (provide file-watcher)
      ;;@doc
      ;; File watcher plugin
      (define (file-watcher)
        (spawn-watcher))
    '';

    file.".gitignore".text = ''
      Session.vim
      .claude/
    '';

    stateVersion = "25.11";
  };
  gtk = {
    gtk2.force = true;
  };

  xdg = {
    configFile = {
      "gtk-3.0/gtk.css".force = true;
      "gtk-4.0/gtk.css".force = true;
      "vkBasalt/vkBasalt.conf".text = ''
        reshadeIncludePath = ${reshade-shaders}
        reshadeTexturePath = ${sweetfx-src}/Textures
        effects = vibrance
        vibrance = ${reshade-shaders}/SweetFX/Vibrance.fx
        Vibrance = 0.5
      '';
    };
  };
}
