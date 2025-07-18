{ pkgs
, config
, ...
}:

{
  stylix = {
    enable = true;
    targets = {
      qt.enable = false;
    };
  };

  home = {
    username = "makano";
    homeDirectory = "/home/makano";

    shell = {
      enableShellIntegration = true;
    };

    sessionVariables = { };

    packages = with pkgs; [
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
      ripgrep
    ];

    stateVersion = "25.11";
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
    yt-dlp = {
      enable = true;
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
        ${builtins.concatStringsSep "\n" (
          builtins.attrValues (
            builtins.mapAttrs (name: value: "set -gx ${name} ${value}") (
              builtins.removeAttrs config.home.sessionVariables [
                "TMUX_TMPDIR"
                "XDG_CONFIG_DIRS"
              ]
            )
          )
        )}
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
    git = {
      enable = true;
      userEmail = "makanobush@gmail.com";
      userName = "Kevin";
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
      enableNushellIntegration = true;
      settings = {
        add_newline = true;
        continuation_prompt = "[▸▹ ](dimmed white)";
        format = "($nix_shell$container$fill$git_metrics\n)$cmd_duration$hostname$localip$shlvl$shell$env_var$jobs$sudo$username$character";
        right_format = "$singularity$kubernetes$directory$vcsh$fossil_branch$git_branch$git_commit$git_state$git_status$hg_branch$pijul_channel$docker_context$package$c$cpp$cmake$cobol$daml$dart$deno$dotnet$elixir$elm$erlang$fennel$golang$guix_shell$haskell$haxe$helm$java$julia$kotlin$gradle$lua$nim$nodejs$ocaml$opa$perl$php$pulumi$purescript$python$raku$rlang$red$ruby$rust$scala$solidity$swift$terraform$vlang$vagrant$zig$buf$conda$pixi$meson$spack$memory_usage$aws$gcloud$openstack$azure$crystal$custom$status$os$battery$time";

        fill = {
          symbol = " ";
        };

        character = {
          format = "$symbol ";
          success_symbol = "[◎](bold italic bright-yellow)";
          error_symbol = "[○](italic purple)";
          vimcmd_symbol = "[■](italic dimmed green)";
          vimcmd_replace_one_symbol = "◌";
          vimcmd_replace_symbol = "□";
          vimcmd_visual_symbol = "▼";
        };

        env_var = {
          VIMSHELL = {
            format = "[$env_value]($style)";
            style = "green italic";
          };
        };

        sudo = {
          format = "[$symbol]($style)";
          style = "bold italic bright-purple";
          symbol = "⋈┈";
          disabled = false;
        };

        username = {
          style_user = "bright-yellow bold italic";
          style_root = "purple bold italic";
          format = "[⭘ $user]($style) ";
          disabled = false;
          show_always = false;
        };

        directory = {
          home_symbol = "⌂";
          truncation_length = 2;
          truncation_symbol = "□ ";
          read_only = " ◈";
          use_os_path_sep = true;
          style = "italic blue";
          format = "[$path]($style)[$read_only]($read_only_style)";
          repo_root_style = "bold blue";
          repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) [△](bold bright-blue)";
        };

        cmd_duration = {
          format = "[◄ $duration ](italic white)";
        };

        jobs = {
          format = "[$symbol$number]($style) ";
          style = "white";
          symbol = "[▶️](blue italic)";
        };

        localip = {
          ssh_only = true;
          format = " ◯[$localipv4](bold magenta)";
          disabled = false;
        };

        time = {
          disabled = false;
          format = "[ $time]($style)";
          time_format = "%R";
          utc_time_offset = "local";
          style = "italic dimmed white";
        };

        battery = {
          format = "[ $percentage $symbol]($style)";
          full_symbol = "█";
          charging_symbol = "[↑](italic bold green)";
          discharging_symbol = "↓";
          unknown_symbol = "░";
          empty_symbol = "▃";
          display = [
            {
              threshold = 20;
              style = "italic bold red";
            }
            {
              threshold = 60;
              style = "italic dimmed bright-purple";
            }
            {
              threshold = 70;
              style = "italic dimmed yellow";
            }
          ];
        };

        git_branch = {
          format = " [$branch(:$remote_branch)]($style)";
          symbol = "[△](bold italic bright-blue)";
          style = "italic bright-blue";
          truncation_symbol = "⋯";
          truncation_length = 11;
          ignore_branches = [
            "main"
            "master"
          ];
          only_attached = true;
        };

        git_metrics = {
          format = "([▴$added]($added_style))([▿$deleted]($deleted_style))";
          added_style = "italic dimmed green";
          deleted_style = "italic dimmed red";
          ignore_submodules = true;
          disabled = false;
        };
        git_status = {
          style = "bold italic bright-blue";
          format = "([⎪$ahead_behind$staged$modified$untracked$renamed$deleted$conflicted$stashed⎥]($style))";
          conflicted = "[◪◦](italic bright-magenta)";
          ahead = "[▴│[\${count}](bold white)│](italic green)";
          behind = "[▿│[\${count}](bold white)│](italic red)";
          diverged = "[◇ ▴┤[\${ahead_count}](regular white)│▿┤[\${behind_count}](regular white)│](italic bright-magenta)";
          untracked = "[◌◦](italic bright-yellow)";
          stashed = "[◃◈](italic white)";
          modified = "[●◦](italic yellow)";
          staged = "[▪️┤[$count](bold white)│](italic bright-cyan)";
          renamed = "[◎◦](italic bright-blue)";
          deleted = "[✕](italic red)";
        };

        deno = {
          format = " [deno](italic) [∫ $version](green bold)";
          version_format = "\${raw}";
        };

        lua = {
          format = " [lua](italic) [\${symbol}\${version}]($style)";
          version_format = "\${raw}";
          symbol = "⨀ ";
          style = "bold bright-yellow";
        };

        nodejs = {
          format = " [node](italic) [◫ ($version)](bold bright-green)";
          version_format = "\${raw}";
          detect_files = [
            "package-lock.json"
            "yarn.lock"
          ];
          detect_folders = [ "node_modules" ];
          detect_extensions = [ ];
        };

        python = {
          format = " [py](italic) [\${symbol}\${version}]($style)";
          symbol = "[⌉](bold bright-blue)⌊ ";
          version_format = "\${raw}";
          style = "bold bright-yellow";
        };

        ruby = {
          format = " [rb](italic) [\${symbol}\${version}]($style)";
          symbol = "◆ ";
          version_format = "\${raw}";
          style = "bold red";
        };

        rust = {
          format = " [rs](italic) [$symbol$version]($style)";
          symbol = "⊃ ";
          version_format = "\${raw}";
          style = "bold red";
        };

        package = {
          format = " [pkg](italic dimmed) [$symbol$version]($style)";
          version_format = "\${raw}";
          symbol = "◨ ";
          style = "dimmed yellow italic bold";
        };

        swift = {
          format = " [sw](italic) [\${symbol}\${version}]($style)";
          symbol = "◁ ";
          style = "bold bright-red";
          version_format = "\${raw}";
        };

        aws = {
          disabled = true;
          format = " [aws](italic) [$symbol $profile $region]($style)";
          style = "bold blue";
          symbol = "▲ ";
        };

        buf = {
          symbol = "■ ";
          format = " [buf](italic) [$symbol $version $buf_version]($style)";
        };

        c = {
          symbol = "ℂ ";
          format = " [$symbol($version(-$name))]($style)";
        };

        cpp = {
          symbol = "ℂ ";
          format = " [$symbol($version(-$name))]($style)";
        };

        conda = {
          symbol = "◯ ";
          format = " conda [$symbol$environment]($style)";
        };

        pixi = {
          symbol = "■ ";
          format = " pixi [$symbol$version ($environment )]($style)";
        };

        dart = {
          symbol = "◁◅ ";
          format = " dart [$symbol($version )]($style)";
        };

        docker_context = {
          symbol = "◧ ";
          format = " docker [$symbol$context]($style)";
        };

        elixir = {
          symbol = "△ ";
          format = " exs [$symbol $version OTP $otp_version ]($style)";
        };

        elm = {
          symbol = "◩ ";
          format = " elm [$symbol($version )]($style)";
        };

        golang = {
          symbol = "∩ ";
          format = " go [$symbol($version )]($style)";
        };

        haskell = {
          symbol = "❯λ ";
          format = " hs [$symbol($version )]($style)";
        };

        java = {
          symbol = "∪ ";
          format = " java [\${symbol}(\${version} )]($style)";
        };

        julia = {
          symbol = "◎ ";
          format = " jl [$symbol($version )]($style)";
        };

        memory_usage = {
          symbol = "▪️▫️▪️ ";
          format = " mem [\${ram}( \${swap})]($style)";
        };

        nim = {
          symbol = "▴▲▴ ";
          format = " nim [$symbol($version )]($style)";
        };
        nix_shell = {
          style = "bold italic dimmed blue";
          symbol = "✶";
          format = "[$symbol nix⎪$state⎪]($style) [$name](italic dimmed white)";
          impure_msg = "[⌽](bold dimmed red)";
          pure_msg = "[⌾](bold dimmed green)";
          unknown_msg = "[◌](bold dimmed yellow)";
        };

        spack = {
          symbol = "◇ ";
          format = " spack [$symbol$environment]($style)";
        };
      };
    };
  };
}
