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
      NIXOS_OZONE_WL = "1";
      OBS_VKCAPTURE = "1";
      WLR_RENDERER = "vulkan";
      MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
      PROTON_ENABLE_WAYLAND = "1";
      PROTON_ENABLE_HDR = "1";
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
      discord
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
      (inputs.mnw.lib.wrap pkgs {
        neovim = pkgs.neovim-unwrapped;
        aliases = [
          "vi"
          "vim"
        ];
        initLua = ''
          require('codebam')
        '';
        providers = {
          ruby.enable = false;
          python3.enable = false;
        };
        plugins = {
          dev.codebam = {
            pure = ../nvim;
          };
          start = with pkgs.vimPlugins; [
            avante-nvim
            blink-cmp
            catppuccin-vim
            commentary
            conform-nvim
            flash-nvim
            friendly-snippets
            fugitive
            gitsigns-nvim
            lazydev-nvim
            lualine-nvim
            luasnip
            nvim-autopairs
            nvim-treesitter.withAllGrammars
            nvim-web-devicons
            oil-nvim
            plenary-nvim
            sensible
            sleuth
            surround
            telescope-nvim
            todo-comments-nvim
          ];
        };
      })
    ];

    stateVersion = "25.11";
  };
}
