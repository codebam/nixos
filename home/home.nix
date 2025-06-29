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
      name = "Bibata-Modern-Ice";
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Bibata-Modern-Ice";
      };
      gtk.enable = true;
    };

    shellAliases = {
      e = "hx";
    };

    sessionVariables = {
      EDITOR = "hx";
      NIXOS_OZONE_WL = "1";
      OBS_VKCAPTURE = "1";
      WLR_RENDERER = "vulkan";
      MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
      PROTON_ENABLE_WAYLAND = "1";
      PROTON_ENABLE_HDR = "1";
      SEARXNG_API_URL = "http://localhost:8081";
    };

    packages = with pkgs; [
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
      (writeShellScriptBin "nvimdiff" ''
        nvim -d $@
      '')
      (pass.withExtensions (
        subpkgs: with subpkgs; [
          pass-otp
          pass-genphrase
        ]
      ))
      grim
      rcm
      ripgrep
      slurp
      weechat
      (discord.override {
        withOpenASAR = true;
        withVencord = true;
      })
      telegram-desktop
      tor-browser
      youtube-music
      element-desktop
      discord-rpc
      pavucontrol
      heroic
      playerctl
      nixd
      nil
      nodejs
      inputs.neovim.packages.${pkgs.system}.default
      gemini-cli
    ];

    file.".gitignore".text = ''
      Session.vim
    '';

    stateVersion = "25.11";
  };
}
