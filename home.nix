{
  pkgs,
  lib,
  config,
  ...
}:

{
  # age = {
  #   identityPaths = [ ./secrets/identities/yubikey-5c.txt ./secrets/identities/yubikey-5c-nfc.txt ];
  #   secrets.github_token.file = ./secrets/github_token.age;
  # };

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
      (pass.withExtensions (
        subpkgs: with subpkgs; [
          pass-otp
          pass-genphrase
        ]
      ))
      bat
      eza
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
    ];

    shellAliases = {
      vi = "${config.programs.neovim.finalPackage}/bin/nvim";
      ls = "${pkgs.eza}/bin/eza";
      sudo = "${pkgs.systemd}/bin/run0";
    };

    stateVersion = "23.11";
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
        terminal = "wezterm";
        menu = "${pkgs.wmenu}/bin/wmenu-run -i -N 1e1e2e -n 89b4fa -M 1e1e2e -m 89b4fa -S 89b4fa -s cdd6f4";
        output = {
          "Dell Inc. Dell AW3821DW #GTIYMxgwABhF" = {
            mode = "3840x1600@143.998Hz";
            adaptive_sync = "off";
            subpixel = "none";
            render_bit_depth = "10";
            allow_tearing = "yes";
            max_render_time = "off";
          };
          "eDP-1" = {
            scale = "1.5";
          };
        };
        input = {
          "*" = {
            events = "disabled";
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
              command = "${pkgs.waybar}/bin/waybar";
              mode = "dock";
              position = "top";
              hiddenState = "hide";
              # trayOutput = "none";
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
            "Control+space" = "exec ${pkgs.swaynotificationcenter}/bin/swaync-client --hide-latest";
            "${modifier}+Control+space" = "exec ${pkgs.swaynotificationcenter}/bin/swaync-client -t";
            "${modifier}+shift+x" = "exec ${(pkgs.writeShellScript "screenshot" ''
              ${pkgs.grim}/bin/grim -t jpeg /tmp/screenshot.jpg && \
              ${pkgs.wl-clipboard}/bin/wl-copy < /tmp/screenshot.jpg
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
            "${modifier}+n" = "exec pkill -SIGUSR1 waybar";
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
          exec '${pkgs.swaynotificationcenter}/bin/swaync'
        '';
    };

  programs = {
    waybar = {
      enable = true;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          mod = "dock";
          height = 31;
          exclusive = true;
          passthrough = false;
          gtk-layer-shell = true;
          modules-left = [
            "custom/padd"
            "custom/l_end"
            "cpu"
            "memory"
            "temperature"
            "custom/r_end"
            "custom/l_end"
            "idle_inhibitor"
            "clock"
            "custom/r_end"
            "custom/l_end"
            "sway/workspaces"
            "custom/r_end"
            "custom/padd"
          ];
          modules-center = [
            "custom/padd"
            "custom/l_end"
            "wlr/taskbar"
            "custom/r_end"
            "custom/padd"
          ];
          modules-right = [
            "custom/padd"
            "custom/l_end"
            "backlight"
            "network"
            "bluetooth"
            "wireplumber"
            "custom/r_end"
            "custom/l_end"
            "tray"
            "battery"
            "custom/r_end"
            "custom/l_end"
            "custom/swaync"
            "custom/r_end"
            "custom/padd"
          ];
          cpu = {
            interval = 10;
            format = "󰍛 {usage}%";
            format-alt = "{icon0}{icon1}{icon2}{icon3}";
            format-icons = [
              "▁"
              "▂"
              "▃"
              "▄"
              "▅"
              "▆"
              "▇"
              "█"
            ];
          };

          memory = {
            interval = 30;
            format = "󰾆 {percentage}%";
            format-alt = "󰾅 {used}GB";
            max-length = 20;
            tooltip = true;
            tooltip-format = " {used:0.1f}GB/{total:0.1f}GB";
          };

          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              activated = "󰥔";
              deactivated = "󰥔";
            };
          };

          clock = {
            format = "{:%R 󰃭 %m·%d·%y}";
            format-alt = "{:%I:%M %p}";
            tooltip-format = "<tt>{calendar}</tt>";
            calendar = {
              mode = "month";
              mode-mon-col = 3;
              on-scroll = 1;
              on-click-right = "mode";
              format = {
                months = "<span color='#ffead3'><b>{}</b></span>";
                weekdays = "<span color='#ffcc66'><b>{}</b></span>";
                today = "<span color='#ff6699'><b>{}</b></span>";
              };
            };
            actions = {
              on-click-right = "mode";
              on-click-forward = "tz_up";
              on-click-backward = "tz_down";
              on-scroll-up = "shift_up";
              on-scroll-down = "shift_down";
            };
          };

          "wlr/taskbar" = {
            format = "{icon}";
            icon-size = 18;
            spacing = 0;
            tooltip-format = "{title}";
            on-click = "activate";
            on-click-middle = "close";
          };

          backlight = {
            device = "intel_backlight";
            format = "{icon}  {percent}%";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ];
            on-scroll-up = "brightnessctl set 1%+";
            on-scroll-down = "brightnessctl set 1%-";
            min-length = 6;
          };

          network = {
            format-wifi = "󰤨  {essid}";
            format-ethernet = "󱘖 Wired";
            tooltip-format = "󱘖  {ipaddr}   {bandwidthUpBytes}   {bandwidthDownBytes}";
            format-linked = "󱘖  {ifname} (No IP)";
            format-disconnected = " Disconnected";
            format-alt = "󰤨  {signalStrength}%";
            interval = 5;
          };

          wireplumber = {
            format = "{icon} {volume}%";
            format-muted = "";
            on-click = "helvum";
            format-icons = [
              ""
              ""
              ""
            ];
          };

          bluetooth = {
            format = "";
            format-disabled = "";
            format-connected = " {num_connections}";
            tooltip-format = " {device_alias}";
            tooltip-format-connected = "{device_enumerate}";
            tooltip-format-enumerate-connected = " {device_alias}";
          };

          tray = {
            icon-size = 18;
            spacing = 5;
          };

          battery = {
            states = {
              good = 95;
              warning = 30;
              critical = 20;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            format-plugged = " {capacity}%";
            format-alt = "{time} {icon}";
            format-icons = [
              "󰂎"
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
            ];
          };

          "custom/l_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/r_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/sl_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/sr_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/rl_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/rr_end" = {
            format = " ";
            interval = "once";
            tooltip = false;
          };

          "custom/padd" = {
            format = "  ";
            interval = "once";
            tooltip = false;
          };
          "custom/swaync" = {
            format = "{}";
            on-click = "${pkgs.swaynotificationcenter}/bin/swaync-client -t";
            tooltip = false;
          };
        };
      };
      style = ''
        * {
            border: none;
            border-radius: 0px;
            font-weight: bold;
            font-size: 14px;
            min-height: 30px;
        }
        @define-color bar-bg rgba(0, 0, 0, 0);
        @define-color main-bg #1e1e2e;
        @define-color sec-bg #313244;
        @define-color main-fg #cdd6f4;
        @define-color wb-act-bg #a6adc8;
        @define-color wb-act-fg #313244;
        @define-color wb-hvr-bg #f5c2e7;
        @define-color wb-hvr-fg #313244;
        window#waybar {
            background: @bar-bg;
        }
        tooltip {
            background: @main-bg;
            color: @main-fg;
            border-radius: 7px;
            border-width: 0px;
        }
        #workspaces button {
            box-shadow: none;
          text-shadow: none;
            padding: 0px;
            border-radius: 9px;
            margin-top: 3px;
            margin-bottom: 3px;
            padding-left: 3px;
            padding-right: 3px;
            color: @main-fg;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.5s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #workspaces button.active, #workspaces button.focused {
            background: @wb-act-bg;
            color: @wb-act-fg;
            margin-left: 3px;
            padding-left: 12px;
            padding-right: 12px;
            margin-right: 3px;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #workspaces button.urgent{
          background: @wb-hvr-bg;
        }
        #workspaces button:hover {
            background: @wb-hvr-bg;
            color: @wb-hvr-fg;
            padding-left: 3px;
            padding-right: 3px;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #taskbar button {
            box-shadow: none;
          text-shadow: none;
            padding: 0px;
            border-radius: 9px;
            margin-top: 3px;
            margin-bottom: 3px;
            padding-left: 3px;
            padding-right: 3px;
            color: @wb-color;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.5s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #taskbar button.active {
            background: @wb-act-bg;
            color: @wb-act-color;
            margin-left: 3px;
            padding-left: 12px;
            padding-right: 12px;
            margin-right: 3px;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #taskbar button:hover {
            background: @wb-hvr-bg;
            color: @wb-hvr-color;
            padding-left: 3px;
            padding-right: 3px;
            animation: gradient_f 20s ease-in infinite;
            transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
        }
        #backlight,
        #battery,
        #bluetooth,
        #custom-cliphist,
        #clock,
        #temperature,
        #cpu,
        #idle_inhibitor,
        #language,
        #memory,
        #custom-mode,
        #mpris,
        #network,
        #wireplumber,
        #taskbar,
        #tray,
        #custom-swaync,
        #window,
        #workspaces,
        #custom-l_end,
        #custom-r_end,
        #custom-sl_end,
        #custom-sr_end,
        #custom-rl_end,
        #custom-rr_end {
            color: @main-fg;
            background: @main-bg;
            opacity: 1;
            margin: 4px 0px 4px 0px;
            padding-left: 4px;
            padding-right: 4px;
            border-top: 1px solid @sec-bg;
            border-bottom: 1px solid @sec-bg;
        }
        #workspaces,
        #taskbar {
            padding: 0px;
        }
        #custom-r_end {
            border-radius: 0px 21px 21px 0px;
            margin-right: 9px;
            padding-right: 3px;
              border-right: 1px solid @sec-bg;
        }
        #custom-l_end {
            border-radius: 21px 0px 0px 21px;
            margin-left: 9px;
            padding-left: 3px;
              border-left: 1px solid @sec-bg;
        }
        #custom-sr_end {
            border-radius: 0px;
            margin-right: 9px;
            padding-right: 3px;
        }
        #custom-sl_end {
            border-radius: 0px;
            margin-left: 9px;
            padding-left: 3px;
        }
        #custom-rr_end {
            border-radius: 0px 7px 7px 0px;
            margin-right: 9px;
            padding-right: 3px;
        }
        #custom-rl_end {
            border-radius: 7px 0px 0px 7px;
            margin-left: 9px;
            padding-left: 3px;
        }
      '';
    };
    librewolf = {
      enable = true;
      settings = {
        "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
      };
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
      sessionVariables = {
        OBS_VKCAPTURE = "1";
        FLATPAK_GL_DRIVERS = "mesa-git";
        WLR_RENDERER = "vulkan";
        MANGOHUD = "1";
        MANGOHUD_CONFIGFILE = "/home/codebam/.config/MangoHud/MangoHud.conf";
        PROTON_ENABLE_WAYLAND = "1";
        PROTON_ENABLE_HDR = "1";
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
        require('lspconfig').ts_ls.setup { on_attach = on_attach }
        require('lspconfig').eslint.setup { on_attach = on_attach }
        require('lspconfig').jdtls.setup { on_attach = on_attach }
        require('lspconfig').kotlin_language_server.setup { on_attach = on_attach }
        require('lspconfig').svelte.setup { on_attach = on_attach }
        require('lspconfig').bashls.setup { on_attach = on_attach }
        require('lspconfig').pyright.setup { on_attach = on_attach }
        require('lspconfig').nil_ls.setup {
          on_attach = on_attach,
          settings = {
            ['nil'] = {
              formatting = {
                command = { "nixfmt" },
              },
            },
          },
        }
        require('lspconfig').clangd.setup { on_attach = on_attach }
        require('lspconfig').html.setup { on_attach = on_attach }
        require('lspconfig').rust_analyzer.setup { on_attach = on_attach }
        require('lspconfig').csharp_ls.setup { on_attach = on_attach }
        require('lspconfig').sqls.setup {}

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
        require("avante_lib").load()
        require("avante").setup({
          provider = "ollama",
          ollama = {
            model = "devstral",
          },
          rag_service = {
            enabled = true,
            host_mount = os.getenv("HOME"),
            provider = "ollama",
            llm_model = "qwen3:14b",
            embed_model = "nomic-embed-text",
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
      '';
      plugins = [
        pkgs.vimPlugins.avante-nvim
        pkgs.vimPlugins.augment-vim
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
          alpha = 1.0;
        };
      };
    };
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
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
    };
  };

  services = {
    swaync = {
      enable = true;
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
