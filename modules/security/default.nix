_: {
  security = {
    acme = {
      acceptTerms = true;
      defaults = {
        email = "codebam@riseup.net";
      };
    };

    polkit = {
      enable = true;
      extraConfig = ''
        // Allow members of the wheel group to execute any action without a
        // prompt, but only from a local, currently-active session. Without the
        // local/active guard this also covered SSH sessions, so anyone who got
        // a shell as a wheel user had passwordless root for every polkit
        // action. Remote sessions still work -- they just have to authenticate.
        polkit.addRule(function(action, subject) {
            if (subject.isInGroup("wheel") && subject.local && subject.active) {
                return polkit.Result.YES;
            }
        });

        // Safe unit check for systemd user services
        polkit.addRule(function(action, subject) {
            var unit = action.lookup("unit");
            if (action.id && action.id.match("org.freedesktop.systemd1.manage-units") &&
                subject.user == "codebam" &&
                unit && unit.match(/^user@\d+\.service$/)) {
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
      # no-op. Restricting userns here would also break rootless podman,
      # distrobox and the bwrap-based agy-sandbox. Recover from git history if
      # the config ever moves to a kernel that has the knob.
    };
    rtkit.enable = true;
    sudo.enable = false;
  };
}
