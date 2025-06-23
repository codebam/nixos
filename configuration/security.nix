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
        // Allow members of the wheel group to execute any actions
        polkit.addRule(function(action, subject) {
            if (subject.isInGroup("wheel")) {
                return polkit.Result.YES;
            }
        });

        // Allow codebam to manage systemd user services without password
        polkit.addRule(function(action, subject) {
            if (action.id.match("org.freedesktop.systemd1.manage-units") &&
                subject.user == "codebam" &&
                action.lookup("unit").match(/^user@\d+\.service$/)) {
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
    rtkit.enable = true;
    sudo.enable = false;
  };
}
