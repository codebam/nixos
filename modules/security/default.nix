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
      packages = [ pkgs.roddhjav-apparmor-rules ];
      policies = {
        firefox = {
          state = "enforce";
          profile =
            let
              rawProfile = builtins.readFile "${pkgs.roddhjav-apparmor-rules}/etc/apparmor.d/groups/browsers/firefox";
              patched = builtins.replaceStrings
                [
                  "@{exec_path} = @{bin}/@{name} @{lib_dirs}/@{name}"
                  "@{lib_dirs} = @{lib}/firefox{,-esr,-beta,-devedition,-nightly} /opt/@{name}"
                ]
                [
                  "@{exec_path} = /nix/store/*-firefox*/bin/{firefox,.firefox-wrapped}"
                  "@{lib_dirs} = /nix/store/*-firefox*/bin /nix/store/*-firefox*/lib/firefox*"
                ]
                rawProfile;
            in
            patched;
        };
        google-chrome = {
          state = "enforce";
          profile =
            let
              rawProfile = builtins.readFile "${pkgs.roddhjav-apparmor-rules}/etc/apparmor.d/groups/browsers/chrome";
              patched = builtins.replaceStrings
                [
                  "@{exec_path} = @{lib_dirs}/@{name}"
                  "@{lib_dirs} = /opt/google/@{name}"
                ]
                [
                  "@{exec_path} = /nix/store/*-google-chrome*/{bin/google-chrome-stable,share/google/chrome/google-chrome}"
                  "@{lib_dirs} = /nix/store/*-google-chrome*/share/google/chrome /nix/store/*-google-chrome*/bin"
                ]
                rawProfile;
            in
            patched;
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
            abi <abi/4.0>,
            include <tunables/global>

            @{name} = feishin
            @{domain} = io.feishin.Feishin
            @{lib_dirs} = /nix/store/*-feishin*/share/feishin /nix/store/*-feishin*/bin
            @{config_dirs} = @{user_config_dirs}/Feishin
            @{cache_dirs} = @{user_cache_dirs}/Feishin

            @{exec_path} = /nix/store/*-feishin*/bin/feishin /nix/store/*-electron*/bin/electron

            profile feishin @{exec_path} flags=(attach_disconnected) {
              include <abstractions/base>
              include <abstractions/common/electron>

              # Extra permissions needed for Feishin
              /nix/store/** r,
              /nix/store/**/bin/electron rix,

              # Site-specific additions and overrides.
              include if exists <local/feishin>
            }
          '';
        };
        discord = {
          state = "enforce";
          profile =
            let
              rawProfile = builtins.readFile "${pkgs.roddhjav-apparmor-rules}/etc/apparmor.d/profiles-a-f/discord";
              patched = builtins.replaceStrings
                [
                  "@{lib_dirs} = /usr/share/@{name} /opt/@{name}"
                  "@{exec_path} = @{bin}/discord{,-ptb} @{lib_dirs}/Discord{,PTB}"
                ]
                [
                  "@{lib_dirs} = /nix/store/*-discord*/opt/Discord"
                  "@{exec_path} = /nix/store/*-discord*/opt/Discord/Discord /nix/store/*-discord*/bin/discord"
                ]
                rawProfile;
            in
            patched;
        };
      };
    };
    rtkit.enable = true;
    sudo.enable = false;
  };
}
