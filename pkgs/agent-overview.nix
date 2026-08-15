{
  writeShellApplication,
  tmux,
  git,
  gnugrep,
  coreutils,
  fzf,

  # Which tmux sessions count as agents. `sesh` and the agent launcher both
  # name their sessions after the repo they run in, so the prefix is the only
  # thing separating an agent session from a shell someone opened by hand.
  sessionPrefix ? "agent-",

  # Seconds between redraws in `--watch`. Every refresh capture-panes each
  # session, which is cheap, but the numbers it reads (context %, cost) only
  # move on Claude's own statusline updates -- faster polling shows nothing new.
  interval ? 5,
}:

writeShellApplication {
  name = "agent-overview";

  runtimeInputs = [
    tmux
    git
    gnugrep
    coreutils
    fzf
  ];

  text = ''
    prefix=${sessionPrefix}
    interval=${toString interval}

    usage() {
      echo "usage: agent-overview [--watch [seconds]]"
      echo "  Lists Claude Code agents running in ''${prefix}* tmux sessions."
      echo "  --watch redraws in place; press a row's number to connect to it."
    }

    watch=0
    case "''${1-}" in
      --watch) watch=1; [ -n "''${2-}" ] && interval=$2 ;;
      -h | --help) usage; exit 0 ;;
      "") ;;
      *) usage >&2; exit 2 ;;
    esac

    fmt_age() {
      local s=$1
      if [ "$s" -lt 60 ]; then printf '%ds' "$s"
      elif [ "$s" -lt 3600 ]; then printf '%dm' "$((s / 60))"
      elif [ "$s" -lt 86400 ]; then printf '%dh%dm' "$((s / 3600))" "$((s % 3600 / 60))"
      else printf '%dd%dh' "$((s / 86400))" "$((s % 86400 / 3600))"
      fi
    }

    # Filled by draw(), read by the key handler: row number -> session name,
    # and the rendered line for each, which is what `/` hands to fzf so the
    # filter list is the table rather than a second, plainer view of it. The
    # loop below runs in this shell (`done < <(...)`, not a pipe), so both
    # arrays survive the function.
    rows=()
    lines=()

    draw() {
      local now sess attached activity pane dir body status branch line ctx cost row
      now=$(date +%s)
      rows=()
      lines=()

      printf '\033[1m%2s  %-20s %-7s %-8s %-30s %-16s %-5s %s\033[0m\n' \
        "#" SESSION STATUS ACTIVE DIR BRANCH CTX COST

      # A session with no panes is a session being torn down; `|| continue`
      # rather than a failure, since this runs on a timer.
      while IFS=$'\t' read -r sess attached activity; do
        case $sess in "$prefix"*) ;; *) continue ;; esac

        pane=$(tmux list-panes -t "$sess" -F '#{pane_id}' | head -1) || continue
        dir=$(tmux display -p -t "$pane" '#{pane_current_path}')

        # Only the footer: the spinner line, the prompt box, the statusline,
        # and a permission dialog if one is up. Everything above that is
        # transcript, where a sentence about waiting on a permission prompt
        # reads exactly like a permission prompt.
        # `|| true` because a pane that has printed nothing yet -- a session
        # opened a second ago, or one running something silent -- gives grep no
        # lines to keep, and a non-zero exit there would take the whole table
        # down with it under `set -o pipefail`.
        body=$(tmux capture-pane -p -t "$pane" | grep -v '^ *$' | tail -12 || true)

        # The spinner, not "esc to interrupt" -- the hint only shows in some
        # states, but the elapsed/token counter is on screen for every second
        # Claude is working: `✻ Galloping… (3s · ↑ 103 tokens)`. The finished
        # form ("Worked for 35s") has no parenthesis, so it cannot match.
        if grep -qE '\([0-9]+[hms].*(tokens|esc to interrupt)' <<<"$body"; then
          status=$'\033[33mbusy\033[0m'
        elif grep -qE 'Do you want|❯ *[0-9]+\.|Yes, and (don|do not)' <<<"$body"; then
          # Waiting on a permission answer. Worth its own colour: it looks
          # exactly like idle from the outside, but nothing moves until
          # someone attaches.
          status=$'\033[35mask\033[0m'
        elif [ "$attached" = 1 ]; then
          status=$'\033[32midle\033[0m'
        else
          status=$'\033[90midle\033[0m'
        fi

        branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo -)

        # Context % and session cost come off Claude's own statusline rather
        # than any API -- it is the one place a session publishes them, and the
        # pane is already captured. Anchored on the ` | NN% | $N.NN ` run so a
        # percentage elsewhere in the transcript cannot match.
        line=$(grep -oE '\| [0-9]+% \| \$[0-9.]+' <<<"$body" | tail -1 || true)
        ctx=$(grep -oE '[0-9]+%' <<<"$line" | tail -1 || true)
        cost=$(grep -oE '\$[0-9.]+' <<<"$line" | tail -1 || true)

        rows+=("$sess")

        # %b on status, because the colour is already an escape sequence and
        # its bytes would otherwise count towards the field width.
        row=$(printf '%2d  %-20s %b%*s %-8s %-30s %-16s %-5s %s' \
          "''${#rows[@]}" "''${sess#"$prefix"}" "$status" 3 "" \
          "$(fmt_age $((now - activity)))" \
          "''${dir/#"$HOME"/\~}" "$branch" "''${ctx:--}" "''${cost:--}")
        lines+=("$row")
        printf '%s\n' "$row"
      done < <(tmux list-sessions -F '#{session_name}	#{session_attached}	#{session_activity}' 2>/dev/null)

      if [ "$watch" = 1 ]; then
        printf '\n\033[90m1-9 connect  ·  / filter  ·  q quit  ·  %s\033[0m\n' "$(date +%H:%M:%S)"
      else
        printf '\n\033[90mattach: tmux attach -t %s<name>   ·  %s\033[0m\n' \
          "$prefix" "$(date +%H:%M:%S)"
      fi
    }

    # Connect this terminal to $1. Inside tmux -- which is where the popup
    # binding puts us -- `attach` would be nesting; switch-client moves the
    # client that opened the popup, and closing the popup then leaves it on the
    # chosen session. Outside tmux there is no client to move, so attach.
    connect() {
      local target=$1
      if [ -n "''${TMUX-}" ]; then
        tmux switch-client -t "$target"
      else
        tmux attach -t "$target"
      fi
    }

    # Number keys only reach nine rows, and typing a name is what the table
    # exists to avoid. Filter over the rendered rows -- session name, directory
    # and branch are all in the line, so any of them narrows it. Prints the
    # chosen session name, nothing if the pick was cancelled.
    filter() {
      local sel n
      [ "''${#rows[@]}" -gt 0 ] || return 0

      # --ansi so the status colours survive; the row number leads each line
      # and is what maps back, since two agents can share a directory name.
      sel=$(printf '%s\n' "''${lines[@]}" |
        fzf --ansi --no-sort --height=100% --reverse \
          --prompt='agent> ' --header='enter connects · esc cancels') || return 0

      [[ $sel =~ ^[[:space:]]*([0-9]+) ]] || return 0
      n=''${BASH_REMATCH[1]}
      [ -n "''${rows[n - 1]-}" ] && printf '%s' "''${rows[n - 1]}"
    }

    if [ "$watch" = 1 ]; then
      # Hide the cursor while the table owns the screen, and put it back on any
      # exit -- including the q and Ctrl-C paths, which leave mid-loop.
      printf '\033[?25l'
      trap 'printf "\033[?25h"' EXIT

      while true; do
        # Home, then clear-to-end after drawing, so the screen does not blink
        # on every redraw the way `clear` makes it.
        printf '\033[H'
        draw
        printf '\033[J'

        # The read timeout is the refresh interval: a keypress acts at once,
        # and the table redraws on its own when none comes. Numbers are the
        # visible row order, which is tmux's session order -- alphabetical, so
        # it only changes when a session appears or dies.
        if read -rsn1 -t "$interval" key; then
          case $key in
            [1-9])
              [ -n "''${rows[key - 1]-}" ] || continue
              connect "''${rows[key - 1]}"
              exit 0
              ;;
            /)
              # fzf draws over the table and restores the screen on exit; the
              # cursor it leaves visible is hidden again by the next redraw.
              picked=$(filter)
              printf '\033[?25l'
              [ -n "$picked" ] || continue
              connect "$picked"
              exit 0
              ;;
            q | $'\e') exit 0 ;;
          esac
        fi
      done
    else
      draw
    fi
  '';

  meta = {
    description = "Status table of Claude Code agents running in tmux sessions";
    mainProgram = "agent-overview";
  };
}
