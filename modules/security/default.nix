{ lib, ... }: {
  # Remote `nixos-rebuild --elevate=run0` runs `systemd-run --uid=0` inside
  # an SSH session, where polkit has no TTY to prompt on. The supported
  # alternative is the target-architecture `polkit-stdin-agent`; ship it in
  # every toplevel (and enable polkit/run0 support) so a deploying host can
  # use `--ask-elevate-password` against a target that predates this change.
  system.tools.nixos-rebuild.enableRun0Elevation = true;

  security = {
    acme = {
      acceptTerms = true;
      defaults = {
        email = "codebam@riseup.net";
      };
    };

    wrappers = {
      pkexec = {
        enable = lib.mkForce false;
      };
    };

    polkit = {
      enable = true;
      extraConfig = ''
        // Allow members of the wheel group to execute any action without a
        // prompt from any local active session -- including user@1000.service's
        // seatless manager session, where the agent harnesses (dsh, Hermes,
        // opencode) run their shells and need run0 for host maintenance such as
        // nix-collect-garbage. SSH sessions stay excluded: they are remote, so
        // `subject.local` is false and they must authenticate
        // (`--ask-elevate-password` covers remote deploys).
        polkit.addRule(function(action, subject) {
            if (subject.isInGroup("wheel") &&
                subject.local &&
                subject.active) {
                return polkit.Result.YES;
            }
        });

        // Safe unit check for systemd user services. Pinned to
        // user@1000.service (codebam): the old ^user@\d+\.service$
        // pattern let any UID's user manager be driven passwordless.
        polkit.addRule(function(action, subject) {
            var unit = action.lookup("unit");
            if (action.id && action.id.match("org.freedesktop.systemd1.manage-units") &&
                subject.user == "codebam" &&
                unit && unit == "user@1000.service") {
                return polkit.Result.YES;
            }
        });
      '';
    };
    pam = {
      services = {
        swaylock = { };
        systemd-run0 = { };
      };
    };
    apparmor = {
      enable = true;
      # No policies here. The six profiles this used to carry were all
      # `flags=(unconfined)` wrapping a bare `userns,` rule -- the Ubuntu idiom
      # for re-permitting unprivileged user namespaces to a named binary when
      # kernel.apparmor_restrict_unprivileged_userns=1. That sysctl does not
      # exist on this kernel (it is an Ubuntu patch; CachyOS ships
      # kernel.unprivileged_userns_clone=1 instead), so every one of them was a
      # no-op. Restricting userns here would also break rootless podman and
      # distrobox. Recover from git history if
      # the config ever moves to a kernel that has the knob.
    };
    rtkit.enable = true;
    sudo.enable = false;
  };
}
