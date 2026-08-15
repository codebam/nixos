{
  config,
  lib,
  pkgs,
  ...
}:

{
  # A running tmux server keeps whatever config it last read, and the bindings
  # in it name store paths -- the agent-overview popup among them. So a rebuild
  # that changes one of those packages leaves the server calling the previous
  # build until someone sources the config again, which looks like the rebuild
  # not having happened.
  #
  # Sourcing is idempotent and only reaches servers that already exist; with no
  # server running there is nothing to update, and the next one starts from the
  # new config anyway. `|| true` because a server that dies between the check
  # and the source is not a failed activation.
  home.activation.reloadTmux = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ${pkgs.tmux}/bin/tmux list-sessions > /dev/null 2>&1; then
      run ${pkgs.tmux}/bin/tmux source-file ${config.xdg.configHome}/tmux/tmux.conf || true
    fi
  '';

  # Shared by every home-manager user (see home/default.nix and
  # desktop/makano-home.nix). Only the parts that were byte-identical between
  # users live here -- starship prompts, fish setup and fzf options genuinely
  # differ per user and stay in the per-user files.
  programs = {
    bash.enable = true;

    carapace = {
      enable = true;
      enableNushellIntegration = true;
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
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
        prepend ${config.home.homeDirectory}/.local/bin |
        append /usr/bin/env
        )
        $env.SSH_AUTH_SOCK = (gpgconf --list-dirs agent-ssh-socket)
        $env.GPG_TTY = (tty)
      '';
    };

    tmux = {
      enable = true;
      terminal = "tmux-256color";
      prefix = "C-a";
      mouse = true;
      keyMode = "vi";
      clock24 = true;
      # extraConfig is a `lines` option, so per-user files append to this.
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

        # ── Working with agents ────────────────────────────────────────────
        # An agent pane emits far more than a shell does, and some of it is not
        # plain text.
        #
        # 100k lines rather than the default 2000: a long agent run scrolls its
        # own start out of history, and the transcript is the thing you go back
        # to. allow-passthrough lets an inner program's escape sequences reach
        # the terminal (inline images, progress protocols) instead of tmux
        # eating them; set-clipboard makes OSC 52 yanks land in the real
        # clipboard, which is the only copy path that survives ssh.
        set -g history-limit 100000
        set -g allow-passthrough on
        set -s set-clipboard on
        set -g focus-events on

        # keyMode = "vi" only affects movement in copy-mode. Selection keeps
        # tmux's own bindings: Space starts a selection, Enter copies, and `v`
        # is rectangle-toggle. Rebind to what vi actually does, since reading
        # agent output is mostly copy-mode work.
        #
        # wl-copy rather than a bare copy-pipe-and-cancel: set-clipboard on
        # covers OSC 52, which the Wayland clipboard only sees if the outer
        # terminal forwards it. Piping to wl-copy is direct and also works when
        # the yank happens over ssh into this host.
        bind -T copy-mode-vi v send-keys -X begin-selection
        bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
        bind -T copy-mode-vi Y send-keys -X copy-pipe-line-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'
        bind -T copy-mode-vi Escape send-keys -X cancel
        bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '${pkgs.wl-clipboard}/bin/wl-copy'

        # Agents finish silently while you are looking at another window. Flag
        # the window instead of interrupting: activity-action other means only
        # windows you are *not* in raise the flag, and visual-activity off
        # keeps it to a status-bar marker rather than a message overlay.
        set -g monitor-activity on
        set -g monitor-bell on
        set -g activity-action other
        set -g visual-activity off

        # Three agent panes look identical without titles. pane_title is set by
        # whatever runs in the pane (printf '\033]2;name\033\\'); fall back to
        # the command name when nothing set one.
        set -g pane-border-status top
        set -g pane-border-format ' #{pane_index} #{?pane_title,#{pane_title},#{pane_current_command}} '
        bind T command-prompt -p title 'select-pane -T "%%"'

        # Popups: reach another repo, git, or a throwaway shell without
        # disturbing the layout the agents are running in. Store paths rather
        # than PATH lookups — a popup gets the login environment, not this
        # shell's, and a missing binary there fails with an empty flash.
        bind f display-popup -E -w 80% -h 60% "${pkgs.sesh}/bin/sesh connect \"\$(${pkgs.sesh}/bin/sesh list | ${pkgs.fzf}/bin/fzf)\""
        bind g display-popup -E -w 90% -h 90% "${pkgs.lazygit}/bin/lazygit"
        bind - display-popup -E -w 80% -h 70% "$SHELL"

        # Which agents are running, working, or stuck on a permission prompt.
        # --watch redraws in place, so the popup stays live while it is open,
        # and a row's number switches this client to that agent -- the popup
        # exits with it, leaving the session it picked on screen. q closes it.
        bind A display-popup -E -w 90% -h 50% "${pkgs.agent-overview}/bin/agent-overview --watch"

        # Multi-agent ergonomics. respawn-pane -k restarts a wedged agent in
        # place, keeping the layout; synchronize-panes types one command into
        # every pane of the window, which is how you restart or re-prompt a row
        # of agents at once — it stays off unless toggled, since a stray
        # keystroke otherwise goes everywhere.
        bind S set-window-option synchronize-panes \; display "sync #{?pane_synchronized,on,off}"
        bind r respawn-pane -k
        bind C-l select-layout main-vertical
        set -g main-pane-width 60%
      '';
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      tmux = {
        enableShellIntegration = true;
      };
    };
  };
}
