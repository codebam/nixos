{
  writeShellApplication,
  tmux,
  git,
  gnugrep,
  coreutils,

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
  ];

  text = ''
    prefix=${sessionPrefix}
    interval=${toString interval}

    usage() {
      echo "usage: agent-overview [--watch [seconds]]"
      echo "  Lists Claude Code agents running in ''${prefix}* tmux sessions."
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

    draw() {
      local now sess attached activity pane dir body status branch line ctx cost
      now=$(date +%s)

      printf '\033[1m%-20s %-7s %-8s %-30s %-16s %-5s %s\033[0m\n' \
        SESSION STATUS ACTIVE DIR BRANCH CTX COST

      # A session with no panes is a session being torn down; `|| continue`
      # rather than a failure, since this runs on a timer.
      while IFS=$'\t' read -r sess attached activity; do
        case $sess in "$prefix"*) ;; *) continue ;; esac

        pane=$(tmux list-panes -t "$sess" -F '#{pane_id}' | head -1) || continue
        dir=$(tmux display -p -t "$pane" '#{pane_current_path}')

        # 60 lines is enough to hold Claude's footer -- the prompt box, the
        # statusline and any permission dialog above it -- without pulling in
        # so much transcript that a stale "esc to interrupt" from an earlier
        # turn is still in the window and reads as busy.
        body=$(tmux capture-pane -p -t "$pane" -S -60)

        if grep -qi 'esc to interrupt' <<<"$body"; then
          status=$'\033[33mbusy\033[0m'
        elif grep -qE 'Do you want|Allow .* to' <<<"$body"; then
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

        # %b on status, because the colour is already an escape sequence and
        # its bytes would otherwise count towards the field width.
        printf '%-20s %b%*s %-8s %-30s %-16s %-5s %s\n' \
          "''${sess#"$prefix"}" "$status" 3 "" \
          "$(fmt_age $((now - activity)))" \
          "''${dir/#"$HOME"/\~}" "$branch" "''${ctx:--}" "''${cost:--}"
      done < <(tmux list-sessions -F '#{session_name}	#{session_attached}	#{session_activity}' 2>/dev/null)

      printf '\n\033[90mattach: tmux attach -t %s<name>   ·  %s\033[0m\n' \
        "$prefix" "$(date +%H:%M:%S)"
    }

    if [ "$watch" = 1 ]; then
      while true; do
        # Home, then clear-to-end after drawing, so the screen does not blink
        # on every redraw the way `clear` makes it.
        printf '\033[H'
        draw
        printf '\033[J'
        sleep "$interval"
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
