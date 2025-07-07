{ lib
, inputs
, config
, ...
}:
{
  nixpkgs = {
    config = {
      # checkMeta = true;
      # showDerivationWarnings = [ "maintainerless" ];
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "steam"
          "steam-original"
          "steam-run"
          "steam-unwrapped"
          "open-webui"
          "discord"
          "discord-ptb"
          "discord-canary"
          "steamdeck-hw-theme"
          "steam-jupiter-unwrapped"
          "libretro-genesis-plus-gx"
          "libretro-snes9x"
          "libretro-fbneo"
          "libretro-mame2000"
          "libretro-mame2003"
          "libretro-mame2015"
          "vscode"
          "via"
          "claude-code"
          "google-cloud-sdk"
        ];
    };
    overlays = [
      (final: prev: {
        foot = prev.foot.overrideAttrs (new: old: {
          version = "0-unstable-2025-07-03";
          src = prev.fetchFromGitea {
            domain = "codeberg.org";
            owner = "dnkl";
            repo = "foot";
            rev = "968bc05c32a2e68282fd28e840b06ac63556d82e";
            hash = "sha256-p9PJFJ1lj4nPbdBpSV6JM3XmBjnucSUdFPwq52Gp/fM=";
          };
        });
        fish = prev.fish.overrideAttrs (
          new: old: {
            stdenv = prev.ccacheStdenv;
            version = "4.1.0-alpha0-unstable-2025-07-03";
            src = prev.fetchFromGitHub {
              owner = "fish-shell";
              repo = "fish-shell";
              rev = "e9bb150a41b64bc0d4cd3784d6fd54e0eabb4b42";
              hash = "sha256-Hia69h9A6dkeEd6sBDPWmTVr/3OCZujasyp6I2Qwoyc=";
            };
            cargoDeps = prev.rustPlatform.fetchCargoVendor {
              inherit (new) src patches;
              hash = "sha256-HFY3/upUnc1CYhxFq8MOSaN6ZnnC/ScyPiYzdG77Wu4=";
            };
            postPatch =
              ''
                substituteInPlace src/builtins/tests/test_tests.rs \
                  --replace-fail '"/bin/ls"' '"${lib.getExe' prev.coreutils "ls"}"'

                substituteInPlace src/highlight/tests.rs \
                  --replace-fail '"/bin/echo"' '"${lib.getExe' prev.coreutils "echo"}"' \
                  --replace-fail '"/bin/c"' '"${lib.getExe' prev.coreutils "c"}"' \
                  --replace-fail '"/bin/ca"' '"${lib.getExe' prev.coreutils "ca"}"' \
                  --replace-fail '/usr' '/'

                substituteInPlace tests/checks/cd.fish \
                  --replace-fail '/bin/pwd' '${lib.getExe' prev.coreutils "pwd"}'

                substituteInPlace tests/checks/redirect.fish \
                  --replace-fail '/bin/echo' '${lib.getExe' prev.coreutils "echo"}'

                substituteInPlace tests/checks/vars_as_commands.fish \
                  --replace-fail '/usr/bin' '${prev.coreutils}/bin'

                substituteInPlace tests/checks/jobs.fish \
                  --replace-fail 'ps -o' '${lib.getExe' prev.procps "ps"} -o' \
                  --replace-fail '/bin/echo' '${lib.getExe' prev.coreutils "echo"}'

                substituteInPlace tests/checks/job-control-noninteractive.fish \
                  --replace-fail '/bin/echo' '${lib.getExe' prev.coreutils "echo"}'

                substituteInPlace tests/checks/complete.fish \
                  --replace-fail '/bin/ls' '${lib.getExe' prev.coreutils "ls"}'

                # Several pexpect tests are flaky
                # See https://github.com/fish-shell/fish-shell/issues/8789
                rm tests/pexpects/exit_handlers.py
                rm tests/pexpects/private_mode.py
                rm tests/pexpects/history.py
              ''
              + lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
                # Tests use pkill/pgrep which are currently not built on Darwin
                # See https://github.com/NixOS/nixpkgs/pull/103180
                # and https://github.com/NixOS/nixpkgs/issues/141157
                rm tests/pexpects/exit.py
                rm tests/pexpects/job_summary.py
                rm tests/pexpects/signals.py
                rm tests/pexpects/fg.py
              ''
              + lib.optionalString (prev.stdenv.hostPlatform.isAarch64 || prev.stdenv.hostPlatform.isDarwin) ''
                # This test seems to consistently fail on aarch64 and darwin
                rm tests/checks/cd.fish
              '';
          }
        );
        ccacheWrapper = prev.ccacheWrapper.override {
          extraConfig = ''
            export CCACHE_COMPRESS=1
            export CCACHE_DIR="${config.programs.ccache.cacheDir}"
            export CCACHE_UMASK=007
            if [ ! -d "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' does not exist"
              echo "Please create it with:"
              echo "  sudo mkdir -m0770 '$CCACHE_DIR'"
              echo "  sudo chown root:nixbld '$CCACHE_DIR'"
              echo "====="
              exit 1
            fi
            if [ ! -w "$CCACHE_DIR" ]; then
              echo "====="
              echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami)"
              echo "Please verify its access permissions"
              echo "====="
              exit 1
            fi
          '';
        };
        # inherit (inputs.librewolf.legacyPackages.${prev.system}) librewolf-unwrapped;
        wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            rev = "f4327f52cf18fea41c08e054012b5a85967b18b1";
            hash = "sha256-oNKyITN9tCiEyvFBNrlilxcSnvrXqsA7poP/uWP2Hd0=";
          };
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "a1ac2a2e93ffb3341253af30603cf16483d766bb";
            hash = "sha256-+Horc7rdcgHMz0Pr5EaLtbaibzToQLjqv3+vj1J1RzM=";
          };
          patches = old.patches ++ [
            (prev.fetchurl {
              url = "https://github.com/swaywm/sway/compare/master..emersion:hdr10.patch";
              hash = "sha256-wekk6bXwiSL0VCgJGEXuiMUGv9MxjG/8JmDfHlMtBMo=";
            })
          ];
        });
      })
    ];
  };
}
