{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

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
      nixfmt-tree
      age-plugin-yubikey
      discord
      telegram-desktop
      tor-browser
      youtube-music
      element-desktop
      discord-rpc
      pavucontrol
      heroic
      playerctl
    ];

    shellAliases = {
      vi = "${config.programs.neovim.finalPackage}/bin/nvim";
    };

    stateVersion = "25.11";
  };

  wayland.windowManager.sway =
    let
      modifier = "Mod4";
    in
    {
      enable = true;
      systemd.enable = true;
      config = rec {
        inherit modifier;
        terminal = "${pkgs.foot}/bin/foot";
        menu = "${pkgs.wmenu}/bin/wmenu-run -f \"Fira Code NerdFont 11\" -i -N 1e1e2e -n 89b4fa -M 1e1e2e -m 89b4fa -S 89b4fa -s cdd6f4";
        seat = {
          "*" = {
            xcursor_theme = "Bibata-Modern-Ice";
          };
        };
        output = {
          "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
            mode = "3840x1600@143.998Hz";
            adaptive_sync = "off";
            subpixel = "none";
            render_bit_depth = "8";
            allow_tearing = "yes";
            max_render_time = "off";
          };
          "eDP-1" = {
            scale = "1.5";
          };
        };
        input = {
          "*" = {
            events = "enabled";
          };
          "1133:49291:Logitech_G502_HERO_Gaming_Mouse" = {
            events = "enabled";
          };
          "13364:832:Keychron_Keychron_V4" = {
            events = "enabled";
          };
          "1739:0:Synaptics_TM3289-021" = {
            events = "enabled";
            dwt = "enabled";
            tap = "enabled";
            natural_scroll = "enabled";
            middle_emulation = "enabled";
            pointer_accel = "0.2";
            accel_profile = "adaptive";
          };
          "2:10:TPPS/2_Elan_TrackPoint" = {
            events = "enabled";
            pointer_accel = "0.7";
            accel_profile = "adaptive";
          };
        };
        bars = [
          (lib.mkMerge [
            config.lib.stylix.sway.bar
            {
              statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
              mode = "dock";
              fonts = lib.mkForce {
                names = [ "Fira Code NerdFont" ];
                size = 11.0;
              };
              position = "top";
              hiddenState = "hide";
              trayOutput = "none";
              colors.background = lib.mkForce "#00000000";
            }
          ])
        ];
        window = {
          titlebar = false;
          border = 1;
          hideEdgeBorders = "smart";
        };
        floating = {
          titlebar = false;
          border = 1;
        };
        gaps = {
          inner = 15;
          smartGaps = true;
        };
        focus.followMouse = false;
        workspaceAutoBackAndForth = true;
        keybindings =
          let
            inherit modifier;
          in
          lib.mkOptionDefault {
            "${modifier}+p" = "exec ${pkgs.swaylock}/bin/swaylock";
            "${modifier}+shift+p" = "exec ${pkgs.swaylock}/bin/swaylock & systemctl suspend";
            "${modifier}+shift+u" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
            "${modifier}+shift+y" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "${modifier}+shift+i" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl next";
            "shift+XF86Macro1" = "exec ${pkgs.playerctl}/bin/playerctl previous";
            "Control+space" = "exec ${pkgs.mako}/bin/makoctl dismiss";
            "${modifier}+Control+space" = "exec ${pkgs.mako}/bin/makoctl restore";
            "${modifier}+space" = "exec ${pkgs.mako}/bin/makoctl invoke default";
            "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim - < "$temp_file" | ${pkgs.wl-clipboard}/bin/wl-copy
              ${pkgs.grim}/bin/grim $HOME/Pictures/Screenshots/screenshot-$(date +%Y%m%d%H%M%S).png
            '')}";
            "${modifier}+x" = "exec ${(pkgs.writeShellScript "screenshot-select" ''
              temp_file=$(mktemp /tmp/screenshot-XXXXXX.png)
              ${pkgs.grim}/bin/grim "$temp_file"
              ${pkgs.imv}/bin/imv -f "$temp_file" &
              imv_pid=$!
              sleep 0.1
              region=$(${pkgs.slurp}/bin/slurp)
              if [ -n "$region" ]; then
                  ${pkgs.grim}/bin/grim -g "$region" - < "$temp_file" | ${pkgs.wl-clipboard}/bin/wl-copy
                  ${pkgs.grim}/bin/grim -g "$region" $HOME/Pictures/Screenshots/screenshot-$(date +%Y%m%d%H%M%S).png
              fi
              kill $imv_pid
              rm "$temp_file"
            '')}";
            "${modifier}+n" = "exec '${pkgs.sway}/bin/swaymsg \"bar mode toggle\"'";
            "XF86AudioRaiseVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+";
            "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-";
            "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set +1%";
            "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 1%-";
          };
      };
      extraConfig =
        let
          inherit modifier;
        in
        ''
          bindsym --whole-window {
            ${modifier}+Shift+button4 exec "${pkgs.brightnessctl}/bin/brightnessctl set +1%"
            ${modifier}+Shift+button5 exec "${pkgs.brightnessctl}/bin/brightnessctl set 1%-"
            ${modifier}+button4 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%+"
            ${modifier}+button5 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%-"
          }
          exec '${pkgs.mako}/bin/mako'
        '';
    };

  programs = {
    carapace = {
      enable = true;
      enableNushellIntegration = true;
    };
    nushell = {
      enable = true;
      extraConfig = ''
        let carapace_completer = {|spans|
        carapace $spans.0 nushell ...$spans | from json
        }
        $env.config = {
         show_banner: false,
         completions: {
         case_sensitive: false
         quick: true
         partial: true
         algorithm: "fuzzy"
         external: {
             enable: true 
             max_results: 100 
             completer: $carapace_completer # check 'carapace_completer' 
           }
         }
        } 
        $env.PATH = ($env.PATH | 
        split row (char esep) |
        prepend /home/myuser/.apps |
        append /usr/bin/env
        )
        $env.SSH_AUTH_SOCK = (gpgconf --list-dirs agent-ssh-socket)
        $env.GPG_TTY = (tty)
      '';
    };
    i3status-rust = {
      enable = true;
    };
    librewolf = {
      enable = true;
    };
    yt-dlp = {
      enable = true;
    };
    mpv = {
      enable = true;
      config = {
        save-position-on-quit = true;
        resume-playback = true;
      };
    };
    obs-studio = {
      enable = true;
      plugins = [ pkgs.obs-studio-plugins.obs-vaapi ];
    };
    swaylock = {
      enable = true;
    };
    mangohud = {
      enable = true;
      settings = {
        preset = 4;
        gamemode = true;
        hdr = true;
        full = true;
      };
    };
    wezterm = {
      enable = true;
      extraConfig = ''
        return {
          window_background_opacity = 0.9,
          hide_tab_bar_if_only_one_tab = true,
          window_padding = {
            left = 0,
            right = 0,
            top = 0,
            bottom = 0,
          }
        }
      '';
    };
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };
    gh-dash = {
      enable = true;
    };
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting ""
        set -gx NIXOS_OZONE_WL 1
        set -gx OBS_VKCAPTURE 1
        set -gx WLR_RENDERER vulkan
        set -gx MANGOHUD_CONFIGFILE /home/codebam/.config/MangoHud/MangoHud.conf
        set -gx PROTON_ENABLE_WAYLAND 1
        set -gx PROTON_ENABLE_HDR 1
      '';
      plugins = [
        {
          name = "autopair.fish";
          src = pkgs.fetchFromGitHub {
            owner = "jorgebucaran";
            repo = "autopair.fish";
            rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
            sha256 = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
          };
        }
        {
          name = "puffer-fish";
          src = pkgs.fetchFromGitHub {
            owner = "nickeb96";
            repo = "puffer-fish";
            rev = "12d062eae0ad24f4ec20593be845ac30cd4b5923";
            sha256 = "sha256-2niYj0NLfmVIQguuGTA7RrPIcorJEPkxhH6Dhcy+6Bk=";
          };
        }
      ];
    };
    bash = {
      enable = true;
    };
    neovim = {
      enable = true;
      defaultEditor = true;
      extraLuaPackages = ps: [ ps.jsregexp ];
      extraLuaConfig = ''

        require('nvim-treesitter.configs').setup {
          auto_install = false,
          ignore_install = {},
          highlight = {
            enable = true,
            additional_vim_regex_highlighting = false,
          },
          indent = {
            enable = true
          },
        }

        local on_attach = function(client, bufnr)
          require("lsp-format").on_attach(client, bufnr)
        end

        require("lsp-format").setup{}
        vim.lsp.enable('ts_ls')
        vim.lsp.enable('eslint')
        vim.lsp.enable('jdtls')
        vim.lsp.enable('kotlin_language_server')
        vim.lsp.enable('svelte')
        vim.lsp.enable('bashls')
        vim.lsp.enable('pyright')
        vim.lsp.enable('nil_ls')
        vim.lsp.enable('clangd')
        vim.lsp.enable('html')
        vim.lsp.enable('rust_analyzer')
        vim.lsp.enable('csharp_ls')
        vim.lsp.enable('sqls')
        vim.lsp.enable('nil_ls')

        local prettier = {
          formatCommand = [[prettier --stdin-filepath ''${INPUT} ''${--tab-width:tab_width}]],
          formatStdin = true,
        }
        vim.lsp.config['efm'] = {
          on_attach = on_attach,
          init_options = { documentFormatting = true },
          settings = {
            languages = {
              typescript = { prettier },
              html = { prettier },
              javascript = { prettier },
              json = { prettier },
            },
          },
        }
        vim.lsp.enable('efm')

        require("blink.cmp").setup{
          signature = { enabled = true },
        }

        require("avante_lib").load()
        require("avante").setup({
          provider = "ollama",
          providers = {
            ollama = {
              model = "devstral",
            },
            gemini = {
              model = "gemini-2.5-flash-preview-05-20",
            },
          },
          rag_service = {
            enabled = true,
            host_mount = os.getenv("HOME"),
            llm = {
              provider = "ollama",
              endpoint = "http://localhost:11434",
              api_key = "",
              model = "qwen3:14b",
              extra = nil,
            },
            embed = {
              provider = "ollama",
              endpoint = "http://localhost:11434",
              api_key = "",
              model = "nomic-embed-text",
              extra = {
                embed_batch_size = 10,
              },
            },
          },
          cursor_applying_provider = 'ollama',
          behaviour = {
            enable_cursor_planning_mode = true,
          },
        })
      '';
      extraConfig = ''
        set guicursor=n-v-c-i:block
        set nowrap
        colorscheme catppuccin_mocha
        let g:lightline = {
              \ 'colorscheme': 'catppuccin_mocha',
              \ }
        map <leader>ac :lua vim.lsp.buf.code_action()<CR>
        map <leader><space> :nohl<CR>
        nnoremap <leader>ff <cmd>Telescope find_files<cr>
        nnoremap <leader>fd <cmd>Telescope diagnostics<cr>
        nnoremap <leader>fg <cmd>Telescope live_grep<cr>
        nnoremap <leader>fb <cmd>Telescope buffers<cr>
        nnoremap <leader>fh <cmd>Telescope help_tags<cr>
        set ts=2
        set undofile
        set undodir=$HOME/.vim/undodir
        let g:vimsence_client_id = '439476230543245312'
        let g:vimsence_small_text = 'NeoVim'
        let g:vimsence_small_image = 'neovim'
        let g:vimsence_editing_details = 'Editing: {}'
        let g:vimsence_editing_state = 'Working on: {}'
        let g:vimsence_file_explorer_text = 'In :Lexplore'
        let g:vimsence_file_explorer_details = 'Looking for files'
      '';
      plugins = [
        pkgs.vimPlugins.avante-nvim
        pkgs.vimPlugins.augment-vim
        pkgs.vimPlugins.catppuccin-vim
        pkgs.vimPlugins.codi-vim
        pkgs.vimPlugins.commentary
        pkgs.vimPlugins.friendly-snippets
        pkgs.vimPlugins.fugitive
        pkgs.vimPlugins.gitgutter
        pkgs.vimPlugins.telescope-nvim
        pkgs.vimPlugins.lightline-vim
        pkgs.vimPlugins.lsp-format-nvim
        pkgs.vimPlugins.luasnip
        pkgs.vimPlugins.blink-cmp
        pkgs.vimPlugins.nvim-lspconfig
        pkgs.vimPlugins.nvim-web-devicons
        pkgs.vimPlugins.plenary-nvim
        pkgs.vimPlugins.sensible
        pkgs.vimPlugins.sleuth
        pkgs.vimPlugins.surround
        pkgs.vimPlugins.todo-comments-nvim
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
      ];
    };
    git = {
      enable = true;
      userEmail = "codebam@riseup.net";
      userName = "Sean Behan";
      extraConfig = {
        merge = {
          tool = "nvimdiff";
        };
      };
    };
    tmux = {
      enable = true;
      terminal = "tmux-256color";
      prefix = "C-a";
      mouse = true;
      keyMode = "vi";
      clock24 = true;
      extraConfig = ''
        set -ga terminal-overrides ",*256col*:Tc"
        bind-key C-a last-window
        bind-key a send-prefix
        bind-key b set status
        bind s split-window -v
        bind v split-window -h
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R
        set -sg escape-time 300
      '';
    };

    foot = {
      enable = true;
      settings = {
        main = {
          term = "xterm-256color";
        };
        mouse = {
          hide-when-typing = "yes";
        };
        bell = {
          urgent = "yes";
          command = "${pkgs.pipewire}/bin/pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/bell.oga";
          command-focused = "yes";
        };
        colors = {
          alpha = lib.mkForce 0.9;
        };
      };
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = false;
      enableBashIntegration = true;
      enableFishIntegration = true;
      defaultOptions = [
        "--no-height"
        "--no-reverse"
      ];
      tmux = {
        enableShellIntegration = true;
      };
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
    };
  };

  services = {
    mako = {
      enable = true;
      settings = {
        layer = "overlay";
      };
    };
  };

  xdg = {
    enable = true;
  };

  stylix = {
    enable = true;

    targets = {
      mangohud.enable = false;
      librewolf = {
        profileNames = [ "codebam" ];
      };
      nushell.enable = false;
      fish.enable = false;
    };

    polarity = "dark";
    image = builtins.fetchurl {
      url = "https://w.wallhaven.cc/full/2y/wallhaven-2y2wg6.png";
      sha256 = "sha256-nFoNfk7Y/CGKWtscOE5GOxshI5eFmppWvhxHzOJ6mCA=";
    };
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };

      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };

      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "Fira Code NerdFont";
      };

      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };
  };
}
