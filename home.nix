{ pkgs, lib, inputs, ... }:

{
  home = {
    username = "codebam";
    homeDirectory = "/home/codebam";

    packages = with pkgs; [
      (writeShellScriptBin "spaste" ''
        ${curl}/bin/curl -X POST --data-binary @- https://p.seanbehan.ca
      '')
      (writeShellScriptBin "nvimdiff" ''
        nvim -d $@
      '')
      (pass.withExtensions (subpkgs: with subpkgs; [
        pass-otp
        pass-genphrase
      ]))
      bat
      eza
      grim
      rcm
      ripgrep
      slurp
      weechat
    ];

    shellAliases = {
      vi = "nvim";
      ls = "eza";
      sudo = "run0";
    };

    stateVersion = "23.11";
  };
  wayland.windowManager.sway =
    let
      wallpaper = builtins.fetchurl {
        url = "https://images.hdqwalls.com/download/1/beach-seaside-digital-painting-4k-05.jpg";
        sha256 = "2877925e7dab66e7723ef79c3bf436ef9f0f2c8968923bb0fff990229144a3fe";
      };
      modifier = "Mod4";
    in
    {
      extraConfigEarly = ''
        set $rosewater #f5e0dc
        set $flamingo #f2cdcd
        set $pink #f5c2e7
        set $mauve #cba6f7
        set $red #f38ba8
        set $maroon #eba0ac
        set $peach #fab387
        set $yellow #f9e2af
        set $green #a6e3a1
        set $teal #94e2d5
        set $sky #89dceb
        set $sapphire #74c7ec
        set $blue #89b4fa
        set $lavender #b4befe
        set $text #cdd6f4
        set $subtext1 #bac2de
        set $subtext0 #a6adc8
        set $overlay2 #9399b2
        set $overlay1 #7f849c
        set $overlay0 #6c7086
        set $surface2 #585b70
        set $surface1 #45475a
        set $surface0 #313244
        set $base #1e1e2e
        set $mantle #181825
        set $crust #11111b
      '';
      enable = true;
      systemd.enable = true;
      config = rec {
        inherit modifier;
        terminal = "wezterm";
        menu = "${pkgs.wmenu}/bin/wmenu-run -i -N 1e1e2e -n 89b4fa -M 1e1e2e -m 89b4fa -S 89b4fa -s cdd6f4";
        fonts = {
          names = [ "Noto Sans" "FontAwesome" ];
          style = "Bold Semi-Condensed";
          size = 11.0;
        };
        colors = {
          focused = {
            background = "$lavender";
            border = "$base";
            childBorder = "$lavender";
            indicator = "$rosewater";
            text = "$text";
          };
          focusedInactive = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$rosewater";
            text = "$text";
          };
          unfocused = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$rosewater";
            text = "$text";
          };
          urgent = {
            background = "$peach";
            border = "$base";
            childBorder = "$peach";
            indicator = "$overlay0";
            text = "$peach";
          };
          placeholder = {
            background = "$overlay0";
            border = "$base";
            childBorder = "$overlay0";
            indicator = "$overlay0";
            text = "$text";
          };
          background = "$base";
        };
        output = {
          "*" = {
            bg = "${wallpaper} fill";
          };
          "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
            mode = "3840x1600@143.998Hz";
            adaptive_sync = "on";
            subpixel = "none";
          };
          "eDP-1" = {
            scale = "1.5";
          };
        };
        input = {
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
        bars = [{
          position = "top";
          # statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-default.toml";
          statusCommand = "{pkgs.i3status}/bin/i3status";
          hiddenState = "hide";
          trayOutput = "none";
          fonts = {
            names = [ "Fira Code" "FontAwesome" ];
            style = "Bold Semi-Condensed";
            size = 11.0;
          };
          colors = {
            background = "$base";
            statusline = "$text";
            focusedStatusline = "$text";
            focusedSeparator = "$base";
            focusedWorkspace = {
              background = "$base";
              border = "$base";
              text = "$green";
            };
            activeWorkspace = {
              background = "$base";
              border = "$base";
              text = "$blue";
            };
            inactiveWorkspace = {
              background = "$base";
              border = "$base";
              text = "$surface1";
            };
            urgentWorkspace = {
              background = "$base";
              border = "$base";
              text = "$surface1";
            };
            bindingMode = {
              background = "$base";
              border = "$base";
              text = "$surface1";
            };
          };
        }];
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
        keybindings = let inherit modifier; in lib.mkOptionDefault {
          "${modifier}+p" = "exec ${pkgs.swaylock}/bin/swaylock";
          "${modifier}+shift+p" = "exec ${pkgs.swaylock}/bin/swaylock & systemctl suspend";
          "${modifier}+shift+u" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
          "${modifier}+shift+y" = "exec ${pkgs.playerctl}/bin/playerctl previous";
          "${modifier}+shift+i" = "exec ${pkgs.playerctl}/bin/playerctl next";
          "Control+space" = "exec ${pkgs.mako}/bin/makoctl dismiss";
          "${modifier}+Control+space" = "exec ${pkgs.mako}/bin/makoctl restore";
          "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
          ${pkgs.grim}/bin/grim /tmp/screenshot.png && \
          spaste < /tmp/screenshot.png | tr -d '\n' | ${pkgs.wl-clipboard}/bin/wl-copy
          '')}";
          "${modifier}+x" = "exec ${(pkgs.writeShellScript "screenshot-select" ''
          ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" /tmp/screenshot.png && \
          spaste < /tmp/screenshot.png | tr -d '\n' | ${pkgs.wl-clipboard}/bin/wl-copy
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
      extraConfig = let inherit modifier; in ''
        bindsym --whole-window {
          ${modifier}+Shift+button4 exec "${pkgs.brightnessctl}/bin/brightnessctl set +1%"
          ${modifier}+Shift+button5 exec "${pkgs.brightnessctl}/bin/brightnessctl set 1%-"
          ${modifier}+button4 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%+"
          ${modifier}+button5 exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 1%-"
        }
      '';
    };
  programs = {
    wezterm = {
      enable = true;
      extraConfig = ''
        return {
          font = wezterm.font("Fira Code Nerdfont"),
          font_size = 8.0,
          color_scheme = "catppuccin-mocha",
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
    # gh = {
    #   enable = true;
    #   settings = {
    #     git_protocol = "ssh";
    #   };
    # };
    # gh-dash = {
    #   enable = true;
    # };
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };
    # i3status-rust = {
    #   enable = true;
    # };
    swaylock = {
      enable = true;
    };
    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
        function fish_command_not_found
          ${pkgs.nodejs}/bin/node ~/git/cloudflare-ai-cli/src/client.mjs "$argv"
        end
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
      initExtra = ''
        command_not_found_handle() {
          ${pkgs.nodejs}/bin/node ~/git/cloudflare-ai-cli/src/client.mjs "$@"
        }
      '';
      sessionVariables = {
        MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
        FLATPAK_GL_DRIVERS = "mesa-git";
      };
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
        require('lspconfig').ts_ls.setup{ on_attach = on_attach }
        require('lspconfig').eslint.setup{ on_attach = on_attach }
        require('lspconfig').jdtls.setup{ on_attach = on_attach }
        require('lspconfig').kotlin_language_server.setup{ on_attach = on_attach }
        require('lspconfig').svelte.setup{ on_attach = on_attach }
        require('lspconfig').bashls.setup{ on_attach = on_attach }
        require('lspconfig').pyright.setup{ on_attach = on_attach }
        require('lspconfig').nil_ls.setup{ on_attach = on_attach }
        require('lspconfig').clangd.setup{ on_attach = on_attach }
        require('lspconfig').html.setup{ on_attach = on_attach }
        require('lspconfig').rust_analyzer.setup{ on_attach = on_attach }
        require('lspconfig').csharp_ls.setup{ on_attach = on_attach }
        require('lspconfig').sqls.setup{}

        local prettier = {
            formatCommand = [[prettier --stdin-filepath ''${INPUT} ''${--tab-width:tab_width}]],
            formatStdin = true,
        }
        require("lspconfig").efm.setup {
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

        local capabilities = require("cmp_nvim_lsp").default_capabilities()

        local luasnip = require('luasnip')
        require("luasnip.loaders.from_vscode").lazy_load()

        local cmp = require('cmp')
        cmp.setup {
          snippet = {
            expand = function(args)
              luasnip.lsp_expand(args.body)
            end,
          },
          mapping = cmp.mapping.preset.insert({
            ['<C-u>'] = cmp.mapping.scroll_docs(-4), -- Up
            ['<C-d>'] = cmp.mapping.scroll_docs(4), -- Down
            -- C-b (back) C-f (forward) for snippet placeholder navigation.
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<CR>'] = cmp.mapping.confirm {
              behavior = cmp.ConfirmBehavior.Replace,
              select = true,
            },
            ['<Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
              else
                fallback()
              end
            end, { 'i', 's' }),
            ['<S-Tab>'] = cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif luasnip.jumpable(-1) then
                luasnip.jump(-1)
              else
                fallback()
              end
            end, { 'i', 's' }),
          }),
          sources = {
            { name = 'nvim_lsp' },
            { name = 'luasnip' },
          },
        }
        require("trouble").setup {
          opts = {},
          cmd = "Trouble",
          keys = {
            {
              "<leader>xx",
              "<cmd>Trouble diagnostics toggle<cr>",
              desc = "Diagnostics (Trouble)",
            },
            {
              "<leader>xX",
              "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
              desc = "Buffer Diagnostics (Trouble)",
            },
            {
              "<leader>cs",
              "<cmd>Trouble symbols toggle focus=false<cr>",
              desc = "Symbols (Trouble)",
            },
            {
              "<leader>cl",
              "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
              desc = "LSP Definitions / references / ... (Trouble)",
            },
            {
              "<leader>xL",
              "<cmd>Trouble loclist toggle<cr>",
              desc = "Location List (Trouble)",
            },
            {
              "<leader>xQ",
              "<cmd>Trouble qflist toggle<cr>",
              desc = "Quickfix List (Trouble)",
            },
          },
        }
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
        nnoremap <leader>fg <cmd>Telescope live_grep<cr>
        nnoremap <leader>fb <cmd>Telescope buffers<cr>
        nnoremap <leader>fh <cmd>Telescope help_tags<cr>
        set ts=2
        set undofile
        set undodir=$HOME/.vim/undodir
        let g:augment_workspace_folders = ['~/git/seanbehan.ca', '~/git/cf-workers-telegram-bot']
      '';
      plugins = [
        pkgs.vimPlugins.catppuccin-vim
        pkgs.vimPlugins.cmp_luasnip
        pkgs.vimPlugins.cmp-nvim-lsp
        pkgs.vimPlugins.codi-vim
        pkgs.vimPlugins.commentary
        pkgs.vimPlugins.friendly-snippets
        pkgs.vimPlugins.fugitive
        pkgs.vimPlugins.gitgutter
        pkgs.vimPlugins.telescope-nvim
        pkgs.vimPlugins.lightline-vim
        pkgs.vimPlugins.lsp-format-nvim
        pkgs.vimPlugins.luasnip
        pkgs.vimPlugins.nvim-cmp
        pkgs.vimPlugins.nvim-lspconfig
        pkgs.vimPlugins.nvim-web-devicons
        pkgs.vimPlugins.plenary-nvim
        pkgs.vimPlugins.sensible
        pkgs.vimPlugins.sleuth
        pkgs.vimPlugins.surround
        pkgs.vimPlugins.todo-comments-nvim
        pkgs.vimPlugins.trouble-nvim
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
        pkgs.vimPlugins.augment-vim
      ];
    };
    # vim = {
    #   enable = true;
    #   settings = {
    #     background = "dark";
    #     expandtab = true;
    #     ignorecase = true;
    #     shiftwidth = 4;
    #     smartcase = true;
    #     tabstop = 8;
    #     undodir = [ "$HOME/.vim/undodir" ];
    #   };
    #   extraConfig = ''
    #     colorscheme catppuccin_mocha
    #     let g:lightline = {
    #           \ 'colorscheme': 'catppuccin_mocha',
    #           \ }
    #     let g:coc_disable_startup_warning = 1
    #     map <leader>ac <Plug>(coc-codeaction-cursor)
    #   '';
    #   plugins = [
    #     pkgs.vimPlugins.sensible
    #     pkgs.vimPlugins.coc-nvim
    #     pkgs.vimPlugins.coc-pyright
    #     pkgs.vimPlugins.coc-prettier
    #     pkgs.vimPlugins.coc-eslint
    #     pkgs.vimPlugins.coc-snippets
    #     pkgs.vimPlugins.coc-json
    #     pkgs.vimPlugins.coc-svelte
    #     pkgs.vimPlugins.commentary
    #     pkgs.vimPlugins.sleuth
    #     pkgs.vimPlugins.surround
    #     pkgs.vimPlugins.fugitive
    #     pkgs.vimPlugins.gitgutter
    #     pkgs.vimPlugins.vim-javascript
    #     pkgs.vimPlugins.lightline-vim
    #     pkgs.vimPlugins.todo-comments-nvim
    #     pkgs.vimPlugins.vim-snippets
    #     pkgs.vimPlugins.catppuccin-vim
    #   ];
    # };
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
      plugins = with pkgs; [
        # tmuxPlugins.resurrect
      ];
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

    # kitty = {
    #   enable = true;
    #   font = {
    #     name = "Fira Code Nerdfont";
    #     size = 12.0;
    #   };
    #   shellIntegration.mode = "no-cursor";
    #   settings = {
    #     cursor_shape = "block";
    #     cursor_blink_interval = 0;
    #   };
    # };

    foot =
      {
        enable = true;
        settings = {
          main = {
            term = "xterm-256color";
            font = "Fira Code Nerdfont:size=8";
            dpi-aware = "yes";
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
            alpha = 1.0;
          };
        };
      };
    wofi =
      {
        enable = true;
        settings = {
          show = "drun";
          dmenu = true;
          insensitive = true;
          prompt = "";
          width = "25%";
          lines = 5;
          location = "center";
          hide_scroll = true;
          allow_images = true;
        };
      };
    direnv =
      {
        enable = true;
        enableBashIntegration = true;
        nix-direnv.enable = true;
      };
    fzf =
      {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
        defaultOptions = [ "--no-height" "--no-reverse" ];
        tmux = {
          enableShellIntegration = true;
        };
      };

    starship =
      {
        enable = true;
        enableBashIntegration = true;
        enableFishIntegration = true;
      };

    tiny =
      {
        enable = true;
      };

    senpai =
      {
        enable = true;
        config = {
          address = "chat.sr.ht:6697";
          nickname = "codebam";
          password-cmd = [ "pass" "show" "chat.sr.ht" ];
        };
      };

    ncmpcpp = {
      enable = true;
      bindings = [
        { key = "j"; command = "scroll_down"; }
        { key = "k"; command = "scroll_up"; }
        { key = "J"; command = [ "select_item" "scroll_down" ]; }
        { key = "K"; command = [ "select_item" "scroll_up" ]; }
      ];
      settings = {
        song_list_format = " $0%n $1• $8%t $R$0%a ";
        song_columns_list_format = "(3)[]{}(85)[white]{t} (1)[blue]{a}";
        song_status_format = " $3%t $0 $1%a ";
        playlist_display_mode = "columns";
        now_playing_prefix = "$3>";
        now_playing_suffix = "$8$/b";
        browser_playlist_prefix = "$2 ♥ $0 ";
        playlist_disable_highlight_delay = "1";
        message_delay_time= "1";
        progressbar_look = "━━─";
        progressbar_color = "black";
        progressbar_elapsed_color = "green";
        colors_enabled = "yes";
        empty_tag_color = "red";
        statusbar_color = "black";
        state_line_color = "black";
        state_flags_color = "green";
        main_window_color = "green";
        header_window_color = "black";
        display_bitrate = "yes";
        autocenter_mode = "yes";
        centered_cursor = "yes";
        titles_visibility = "no";
        statusbar_visibility = "yes";
        empty_tag_marker=" -- ‼ -- ";
        mouse_support = "no";
        header_visibility = "no";
        display_remaining_time = "no";
        ask_before_clearing_playlists = "no";
        discard_colors_if_item_is_selected = "yes";
      };
    };
    home-manager.enable = true;
  };

  services = {
    # mako = {
    #   enable = true;
    #   layer = "overlay";
    #   font = "Noto Sans";
    #   defaultTimeout = 5000;
    # };
    mopidy = {
      enable = true;
      extensionPackages = with pkgs; [ mopidy-mpd mopidy-ytmusic ];
      settings = {
        ytmusic = {
          oauth_json = "/home/codebam/Downloads/oauth.json";
        };
      };
    };
  };

  gtk =
    {
      # enable = true;
    };

  xdg =
    {
      enable = true;
    };

  catppuccin =
    {
      enable = true;
      flavor = "mocha";
      accent = "blue";
    };
}
