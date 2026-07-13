{ pkgs, ... }: {
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
    apparmor = {
      enable = true;
      policies = {
        firefox = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile firefox /nix/store/*-firefox*/bin/{firefox,.firefox-wrapped} flags=(unconfined) {
              userns,

              # Site-specific additions and overrides. See local/README for details.
              include if exists <local/firefox>
            }
          '';
        };
        google-chrome = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile google-chrome /nix/store/*-google-chrome*/{bin/google-chrome-stable,share/google/chrome/google-chrome} flags=(unconfined) {
              userns,

              # Site-specific additions and overrides.
              include if exists <local/google-chrome>
            }
          '';
        };
        steam = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile steam /nix/store/*-steam* flags=(unconfined) {
              userns,

              # Site-specific additions and overrides.
              include if exists <local/steam>
            }
          '';
        };
        feishin = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile feishin /nix/store/*-feishin*/bin/feishin flags=(unconfined) {
              userns,

              # Site-specific additions and overrides.
              include if exists <local/feishin>
            }
          '';
        };
        electron = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile electron /nix/store/*-electron*/bin/electron flags=(unconfined) {
              userns,

              # Site-specific additions and overrides.
              include if exists <local/electron>
            }
          '';
        };
        discord = {
          state = "enforce";
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile discord /nix/store/*-discord*/opt/Discord/Discord flags=(unconfined) {
              userns,

              # Site-specific additions and overrides.
              include if exists <local/discord>
            }
          '';
        };
      };
    };
    rtkit.enable = true;
    sudo.enable = false;
  };
}
