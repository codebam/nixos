{ pkgs, ... }:

{
  # A VT a remote agent can borrow for a benchmark run.
  #
  # sudo is off on purpose (modules/security/default.nix) and the polkit rule
  # there excludes SSH sessions, so a remote agent cannot elevate here — which
  # is right for a machine that lives in a living room. What a remote benchmark
  # actually needs is not a shell: it is one tty2 session holding the seat for
  # a few minutes, running a fixed harness, and then tty1 back. That is all
  # this unit is, and it is the only thing the rule below allows.
  #
  # `systemctl start viewport-bench@deck.service` runs ~/bench/deck.sh as
  # codebam. The command lives in codebam's home so iterating on the harness
  # needs no rebuild; the unit itself is fixed, so nothing written to /tmp can
  # name it.
  systemd.services."viewport-bench@" = {
    description = "Viewport benchmark on tty2 (%i)";
    serviceConfig = {
      Type = "oneshot";
      # getty@.service does the same: PAMName=login is what registers a logind
      # session, and a session on seat0 is what libseat requires before it will
      # hand a compositor the DRM node. Without it the harness would start and
      # fail at the first device.
      User = "codebam";
      Group = "users";
      PAMName = "login";
      TTYPath = "/dev/tty2";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = false;
      StandardInput = "tty";
      TimeoutStartSec = 600;
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/1000"
        "HOME=/home/codebam"
      ];
      # The one privileged step: activating a VT needs CAP_SYS_TTY_CONFIG.
      # `+` runs this line with the manager's privileges and nothing else.
      ExecStartPre = "+${pkgs.kbd}/bin/chvt 2";
      ExecStart = "${pkgs.bash}/bin/bash /home/codebam/bench/%i.sh";
      ExecStopPost = "+${pkgs.kbd}/bin/chvt 1";
    };
  };

  # The narrow exception to "an SSH session cannot elevate": codebam may start
  # and stop that one templated unit from any session, and nothing else. It is
  # scoped twice — by user and by unit name — so it cannot become a way to
  # manage arbitrary units.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        var unit = action.lookup("unit");
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "codebam" &&
            unit && unit.match(/^viewport-bench@[a-z0-9-]+\.service$/)) {
            return polkit.Result.YES;
        }
    });
  '';
}
