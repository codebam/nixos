# Standalone home-manager profile for the Android Linux Terminal VM on the
# phone (`droid@debian`). The VM keeps its own Debian trixie (aarch64), so it
# cannot take a nixosConfiguration -- only the user environment is managed
# from this repo. Activated on the device with `nh home switch`.
#
# Mirrors the parts of ./home that make sense on a headless phone VM (the
# shell stack from shell-common.nix, the CLI tooling from home.nix and
# programs.nix) and drops the rest deliberately: no compositor, theming, or
# agent harnesses, no GPG agent and no commit signing (there is no YubiKey
# reader in the guest). Keep the overlapping settings in sync with those
# files.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  home = {
    username = "droid";
    homeDirectory = "/home/droid";
    stateVersion = "26.05";

    shell = {
      enableShellIntegration = true;
    };

    sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

    # The inbound half of the managed-keys story: this is the VM's whole
    # authorized set, written from here instead of hand-edited. The desktop's
    # key is the same identity the other hosts carry in
    # modules/users/default.nix; the VM's own key is declared there too, so
    # the ssh trust in both directions lives in the repo.
    #
    # Installed by activation as a real file, NOT as a file."..." entry: that
    # would symlink the keys into /nix/store, and sshd's StrictModes refuses
    # any authorized_keys chain through /nix/store (1775, group-writable):
    # "Authentication refused: bad ownership or modes for directory
    # /nix/store" locked the VM out after its first switch.
    activation.droidAuthorizedKeys = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run install -d -m700 "$HOME/.ssh"
      run install -m600 ${pkgs.writeText "droid-authorized_keys" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEkBfTf9i6kG6P+HGWN3ghszdxQYmXzxllIlxPkwuyCo codebam@nixos-desktop\n"} "$HOME/.ssh/authorized_keys"
    '';

    # Referenced by core.excludesfile below, like home/home.nix does.
    file.".gitignore".text = ''
      Session.vim
      .claude/
    '';

    packages = with pkgs; [
      bat
      dust
      file
      htop
      jq
      lazygit
      nil
      nixd
      nixfmt
      ripgrep
      rsync
      unzip
      # The two by-hand helpers from home/home.nix worth carrying to the
      # phone; the desktop-only ones (sway-kill-parent-fzf, oled-cycle, ...)
      # stay there.
      (writeShellApplication {
        name = "spaste";
        runtimeInputs = [ curl ];
        text = "curl -X POST --data-binary @- https://paste.codebam.ca";
      })
      (writeShellApplication {
        name = "sretry";
        runtimeInputs = [ coreutils ];
        text = ''until "$@"; do sleep 1; done'';
      })
    ];
  };

  # Non-NixOS: PATH/XDG glue so profile binaries and data dirs are found by
  # login shells, tmux, and anything else that reads the session environment.
  targets.genericLinux.enable = true;

  xdg = {
    enable = true;
    # gh replaces the symlink with a real file whenever it writes
    # config.yml, which otherwise aborts the next activation (same reason as
    # home/xdg.nix on the other hosts).
    configFile."gh/config.yml".force = true;
  };

  programs = {
    home-manager.enable = true;

    bash.enable = true;

    # fish stays the VM's login shell (the Terminal app's default); this only
    # gives it the managed config and the session environment.
    fish = {
      enable = true;
      interactiveShellInit = ''set fish_greeting ""'';
    };

    carapace = {
      enable = true;
      enableNushellIntegration = true;
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      # shell-common.nix stops at bash/fish; nushell is the shell this device
      # exists for, so it gets the integration too.
      enableNushellIntegration = true;
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
      enableNushellIntegration = true;
      # defaultOptions from programs.nix; unlike there, the Ctrl-R widget is
      # left alone: there is no Atuin on the VM to take it over.
      defaultOptions = [
        "--height 40%"
        "--layout=reverse"
        "--border"
        "--inline-info"
      ];
    };

    nushell = {
      enable = true;
      # shell-common.nix's config minus the two gpgconf lines: there is no
      # agent socket on the VM to point SSH_AUTH_SOCK at.
      extraConfig = ''
        let carapace_completer = {|spans|
        carapace $spans.0 nushell ...$spans | from json
        }
        $env.config = {
         show_banner: false,
         completions: {
         case_sensitive: false,
         quick: true,
         partial: true,
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
        prepend ${config.home.homeDirectory}/.local/bin |
        append /usr/bin/env
        )
      '';
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableNushellIntegration = true;
      settings = {
        add_newline = false;
        git_metrics.disabled = false;
        gcloud.disabled = true;
        scan_timeout = 10;
        status = {
          disabled = false;
          format = "exited with code [$status](bold red) ";
        };
        character = {
          success_symbol = "\\$(bold green)";
          error_symbol = "[\\$](bold red)";
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
      # Trimmed from shell-common.nix: the desktop-only pieces are gone (the
      # wl-clipboard yanks need Wayland; the sesh/agent-overview popups have
      # no agents to watch here). What stays is the part that matters when a
      # connection can drop: long history, passthrough, and copy-mode.
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

        set -g history-limit 100000
        set -g allow-passthrough on
        set -s set-clipboard on
        set -g focus-events on
        set -g extended-keys on
        set -g extended-keys-format csi-u

        bind -T copy-mode-vi v send-keys -X begin-selection
        bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel
        bind -T copy-mode-vi Y send-keys -X copy-pipe-line-and-cancel
        bind -T copy-mode-vi Escape send-keys -X cancel
        bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel

        set -g monitor-activity on
        set -g monitor-bell on
        set -g activity-action other
        set -g visual-activity off

        set -g pane-border-status top
        set -g pane-border-format ' #{pane_index} #{?pane_title,#{pane_title},#{pane_current_command}} '
        bind T command-prompt -p title 'select-pane -T "%%"'
        bind r respawn-pane -k

        bind g display-popup -E -w 90% -h 90% "${pkgs.lazygit}/bin/lazygit"
        bind - display-popup -E -w 80% -h 70% "$SHELL"
      '';
    };

    fd = {
      enable = true;
      hidden = true;
      ignores = [
        ".git/"
        "*.bak"
      ];
    };

    git = {
      enable = true;
      # Unsigned on purpose: signing is per-host with the YubiKey (programs.nix
      # sets signing.signByDefault for the NixOS hosts); the VM has no key
      # material and nothing to sign with.
      settings = {
        user = {
          email = "codebam@riseup.net";
          name = "Sean Behan";
        };
        pull = {
          rebase = true;
        };
        push = {
          default = "simple";
          autoSetupRemote = true;
        };
        init = {
          defaultBranch = "main";
        };
        core = {
          editor = "hx";
          autocrlf = "input";
          excludesfile = "~/.gitignore";
        };
        diff = {
          colorMoved = "default";
        };
        branch = {
          autosetupmerge = "always";
          autosetuprebase = "always";
        };
      };
    };

    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        prompt = "enabled";
        aliases = {
          co = "pr checkout";
        };
      };
    };

    # Stock Helix, not the hosts' helix_git: the steel plugin config in
    # home/programs.nix needs the _git build plus repo-local .scm files, and
    # that build is a Rust compile the phone should not have to pay for.
    helix = {
      enable = true;
      defaultEditor = true;
    };

    # "Easy ssh": the client config for reaching the desktop, so the VM never
    # hand-manages it. The identity half (id_ed25519) is generated on the
    # device; its public half is declared with the fleet keys in
    # modules/users/default.nix, and the private half is backed up in
    # secrets/secrets.yaml for re-provisioning.
    ssh = {
      enable = true;
      # The module's legacy default block, copied verbatim from the
      # enableDefaultConfig deprecation note in home-manager's ssh module, so
      # the generated config keeps the same values once that option is gone.
      enableDefaultConfig = false;
      settings."*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      settings."nixos-desktop" = {
        user = "codebam";
        identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };

    nh = {
      enable = true;
      flake = "${config.home.homeDirectory}/nixos";
    };
  };
}
