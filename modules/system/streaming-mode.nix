{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.streamingMode;
  systemctl = "${config.systemd.package}/bin/systemctl";

  # `systemctl set-property --runtime` writes drop-ins under
  # /run/systemd/system.control/<unit>.d/, so nothing survives a reboot and
  # nothing is written to the (immutable) store or to /etc. Assigning an empty
  # value is the documented reset: CPUWeight= goes back to the unit default,
  # AllowedCPUs= back to "every CPU". That is why stop can undo start without
  # having to remember what the values were.
  # One invocation per unit: `set-property` takes a single unit followed by its
  # properties, so a space-separated list would be read as a property name.
  setProps =
    name: units: userFlag: props:
    pkgs.writeShellScript name (
      lib.concatMapStringsSep "\n" (
        unit: "${systemctl} ${userFlag} set-property --runtime ${unit} ${lib.concatStringsSep " " props}"
      ) units
    );

  # Weight is a ratio between *siblings*, so it only bites where the busy
  # cgroups actually share a parent. builds.slice is a top-level slice next to
  # user.slice and system.slice, which is the level nix builds and the desktop
  # session compete at. Lowering CPUWeight on nix-daemon.service inside
  # system.slice would have done nothing: if nothing else in system.slice is
  # busy, system.slice still collects its full root-level share.
  systemProps = [
    "CPUWeight=${toString cfg.buildCpuWeight}"
    "IOWeight=${toString cfg.buildIOWeight}"
  ]
  ++ lib.optional (cfg.buildCpus != null) "AllowedCPUs=${cfg.buildCpus}"
  ++ lib.optional (cfg.buildMemoryHigh != null) "MemoryHigh=${cfg.buildMemoryHigh}";

  systemResetProps = [
    "CPUWeight="
    "IOWeight="
  ]
  ++ lib.optional (cfg.buildCpus != null) "AllowedCPUs="
  ++ lib.optional (cfg.buildMemoryHigh != null) "MemoryHigh=";

  streamingMode = pkgs.writeShellApplication {
    name = "streaming-mode";
    runtimeInputs = [
      config.systemd.package
      pkgs.libnotify
    ];
    text = ''
      unit=streaming-mode.service

      notify() {
        # Nothing is wrong if there is no session bus (called over SSH, or from
        # a unit): the cgroup change is the point, the toast is not.
        notify-send -a streaming-mode -i camera-video "Streaming mode" "$1" 2>/dev/null || true
      }

      # The system unit needs polkit (org.freedesktop.systemd1.manage-units);
      # security/default.nix grants that to wheel from a local active session
      # without a prompt, so the sway keybind does not stall on a password.
      # The --user unit needs no authentication at all.
      on() {
        systemctl start "$unit"
        systemctl --user start "$unit"
        notify "on -- builds throttled"
      }

      off() {
        systemctl --user stop "$unit"
        systemctl stop "$unit"
        notify "off -- builds unthrottled"
      }

      status() {
        if systemctl is-active --quiet "$unit"; then
          echo "streaming mode: on"
        else
          echo "streaming mode: off"
        fi
        # The effective values, not the configured ones -- if a drop-in failed
        # to apply, this is where it shows.
        for f in cpu.weight io.weight cpuset.cpus.effective memory.high; do
          if [ -r "/sys/fs/cgroup/builds.slice/$f" ]; then
            echo "  builds.slice $f = $(cat "/sys/fs/cgroup/builds.slice/$f")"
          fi
        done
      }

      case "''${1:-toggle}" in
        on) on ;;
        off) off ;;
        toggle)
          if systemctl is-active --quiet "$unit"; then off; else on; fi
          ;;
        status) status ;;
        *)
          echo "usage: streaming-mode [on|off|toggle|status]" >&2
          exit 2
          ;;
      esac
    '';
  };

  throttled = pkgs.writeShellApplication {
    name = "throttled";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      # Builds started from a shell are children of the terminal's own scope,
      # which sits beside app.slice inside user@$UID.service -- the toggle
      # cannot find them there. Running them through this puts them in the
      # user-level builds.slice instead, which the toggle does throttle.
      #   throttled cargo build
      if [ "$#" -eq 0 ]; then
        echo "usage: throttled <command> [args...]" >&2
        exit 2
      fi
      exec systemd-run --user --scope --collect --quiet \
        --slice=builds.slice --unit="throttled-$$" -- "$@"
    '';
  };
in
{
  options.streamingMode = {
    enable = lib.mkEnableOption ''
      a toggleable cgroup throttle for background builds.

      Off by default at boot; `streaming-mode on` (or the sway keybind) drops
      builds.slice -- nix-daemon and anything run through `throttled` -- to a
      small share of the CPU and, optionally, off a couple of reserved cores,
      so an OBS capture does not compete with a 16-job rebuild. Everything is
      applied as runtime drop-ins, so `streaming-mode off` or a reboot restores
      full speed without a rebuild
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = streamingMode;
      readOnly = true;
      description = ''
        The `streaming-mode on|off|toggle|status` script. Exposed so a
        compositor keybind in home-manager can point at the exact derivation
        this host installs rather than hoping for a PATH lookup.
      '';
    };

    buildCpus = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0-5,8-13";
      description = ''
        CPU list builds are confined to while streaming mode is on
        (systemd AllowedCPUs syntax), or null to leave every CPU available and
        rely on CPUWeight alone.

        Weight alone yields the CPU only under contention, and it yields it a
        scheduling slice at a time -- enough for throughput, not always enough
        to keep an encoder's frame deadline. Excluding a couple of cores gives
        the compositor and encoder somewhere to run that no build can touch.
        Mind SMT: the two threads of a core share it, so a reservation only
        buys a full core if both siblings are excluded. Check pairs with
        `cat /sys/devices/system/cpu/cpu0/topology/thread_siblings_list`.
      '';
    };

    buildCpuWeight = lib.mkOption {
      type = lib.types.ints.between 1 10000;
      default = 10;
      description = ''
        CPUWeight for builds.slice while streaming. Relative to its siblings at
        the root of the hierarchy, user.slice and system.slice, which sit at the
        default 100 -- so 10 is roughly "a tenth of the machine when the desktop
        wants the rest", and the whole machine when the desktop is idle.
      '';
    };

    buildIOWeight = lib.mkOption {
      type = lib.types.ints.between 1 10000;
      default = 10;
      description = ''
        IOWeight for builds.slice while streaming. A build unpacking and
        linking can stall reads elsewhere long enough to drop frames even when
        it is losing the CPU race. Only effective on devices using an
        io.weight-capable scheduler (BFQ); harmless otherwise.
      '';
    };

    buildMemoryHigh = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "16G";
      description = ''
        MemoryHigh for builds.slice while streaming, or null for no limit. This
        is the throttle-and-reclaim knob, not a hard cap: a build that goes over
        is slowed and pushed back to disk rather than killed, which keeps a big
        link step from evicting the page cache the encoder is working out of.
      '';
    };

    extraBuildUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "hermes-agent.service" ];
      description = ''
        Further system units to move into builds.slice, so they are throttled
        alongside nix-daemon. nix-daemon.service is always included.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The slice exists and is unthrottled at boot. Only the toggle changes its
    # properties, so a machine that never streams behaves exactly as before --
    # except that builds now account separately, which is what makes
    # `systemd-cgtop /builds.slice` useful.
    systemd = {
      slices.builds = {
        description = "Background builds (throttled while streaming)";
        sliceConfig = {
          CPUAccounting = true;
          IOAccounting = true;
          MemoryAccounting = true;
        };
      };

      # Sandboxed nix builds are children of nix-daemon.service, so they inherit
      # this placement; there is nothing per-build to catch.
      services =
        lib.genAttrs ([ "nix-daemon" ] ++ map (lib.removeSuffix ".service") cfg.extraBuildUnits) (_: {
          serviceConfig.Slice = "builds.slice";
        })
        // {
          streaming-mode = {
            description = "Throttle background builds so a stream keeps the CPU";
            # Not wantedBy anything: being started *is* the enabled state, and
            # RemainAfterExit is what makes `is-active` the source of truth for
            # the toggle. Reboots therefore come up unthrottled.
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = setProps "streaming-mode-start" [ "builds.slice" ] "" systemProps;
              ExecStop = setProps "streaming-mode-stop" [ "builds.slice" ] "" systemResetProps;
            };
          };
        };

      user = {
        slices.builds = {
          description = "User-started builds (throttled while streaming)";
          sliceConfig = {
            CPUAccounting = true;
            IOAccounting = true;
          };
        };

        services.streaming-mode = {
          description = "Favour the session over user-started builds while streaming";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Inside user@$UID.service the siblings are app.slice (uwsm-launched
            # apps, OBS among them), session.slice (pipewire, wireplumber) and
            # the terminal scopes. Raising the first two is the only way to
            # outrank a compile running in a terminal scope, which systemd
            # leaves at the default 100 and which no unit of ours owns.
            #
            # No AllowedCPUs here: the cpuset controller is not delegated into
            # user@.service, so the reservation only exists at the system level.
            ExecStart = [
              (setProps "streaming-mode-user-start" [ "builds.slice" ] "--user" [
                "CPUWeight=${toString cfg.buildCpuWeight}"
                "IOWeight=${toString cfg.buildIOWeight}"
              ])
              (setProps "streaming-mode-user-apps"
                [
                  "app.slice"
                  "session.slice"
                ] "--user"
                [ "CPUWeight=300" ]
              )
            ];
            ExecStop = [
              (setProps "streaming-mode-user-stop" [ "builds.slice" ] "--user" [
                "CPUWeight="
                "IOWeight="
              ])
              (setProps "streaming-mode-user-apps-reset"
                [
                  "app.slice"
                  "session.slice"
                ] "--user"
                [ "CPUWeight=" ]
              )
            ];
          };
        };
      };
    };

    environment.systemPackages = [
      cfg.package
      throttled
    ];
  };
}
