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

    sessionVariables = {
      EDITOR = "nvim";
      NIXOS_OZONE_WL = "1";
      OBS_VKCAPTURE = "1";
      WLR_RENDERER = "vulkan";
      MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
      PROTON_ENABLE_WAYLAND = "1";
      PROTON_ENABLE_HDR = "1";
      SEARXNG_API_URL = "http://localhost:8081";
    };

    packages = with pkgs; [
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
    ];

    stateVersion = "25.11";
  };
}
