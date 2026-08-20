{
  lib,
  writeShellApplication,
  coreutils,
  gnused,
  pinentry-tty,

  # The terminal a prompt gets its own window in. Only used when a graphical
  # session is there to put a window on; see the fallback below.
  terminal,
}:

writeShellApplication {
  name = "pinentry-auto";

  runtimeInputs = [
    coreutils
    gnused
    pinentry-tty
  ];

  # pinentry-tty draws on whatever tty it is told about and speaks Assuan on
  # its stdio, and those are two independent ends -- which is what makes a
  # window possible at all. The window is a pty holder and nothing else: the
  # pinentry process stays here, attached to the stdio gpg-agent handed us,
  # and is pointed at the new pty with --ttyname. Running pinentry *inside*
  # the terminal would put its protocol on the terminal's pty instead, where
  # gpg-agent cannot reach it.
  text = ''
    term=${lib.getExe terminal}

    fallback() {
      exec pinentry-tty "$@"
    }

    # No graphical session -- a real tty, an ssh login, early boot. There is no
    # window to open, and the tty the caller is on is the only one there is.
    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      fallback "$@"
    fi

    tmp=$(mktemp -d)
    term_pid=""
    cleanup() {
      if [ -n "$term_pid" ]; then
        kill "$term_pid" 2>/dev/null || true
      fi
      rm -rf "$tmp"
    }
    trap cleanup EXIT

    "$term" --title-placeholder pinentry -e sh -c "tty > $tmp/tty; exec sleep 2147483647" &
    term_pid=$!

    # Wall clock, not a handshake: the window reports its pty by writing the
    # file. If it dies or never gets there, the prompt still has to happen, so
    # drop back to the calling tty rather than leaving gpg-agent hanging.
    waited=0
    while [ ! -s "$tmp/tty" ]; do
      if ! kill -0 "$term_pid" 2>/dev/null || [ "$waited" -ge 100 ]; then
        cleanup
        trap - EXIT
        fallback "$@"
      fi
      sleep 0.1
      waited=$((waited + 1))
    done
    pts=$(cat "$tmp/tty")

    # gpg-agent passes the *client's* tty and TERM as Assuan OPTIONs after
    # start-up, which would override -T/-N, so rewrite those two lines in
    # flight. xterm-256color rather than the window's own $TERM: pinentry
    # looks the name up in the terminfo database it was built against, and a
    # terminal shipping its own entry (rio, ghostty) may not be in there.
    sed -u \
      -e "s|^OPTION ttyname=.*|OPTION ttyname=$pts|" \
      -e "s|^OPTION ttytype=.*|OPTION ttytype=xterm-256color|" \
      | pinentry-tty --ttyname "$pts" --ttytype xterm-256color "$@"
  '';

  meta = {
    description = "pinentry-tty in a terminal window of its own, falling back to the calling tty";
    mainProgram = "pinentry-auto";
  };
}
