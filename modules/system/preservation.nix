_: {
  # SSH host keys (modules/services/default.nix: path =
  # "/persistent/etc/ssh/...") and the SOPS age key
  # (desktop/configuration/sops.nix: keyFile =
  # "/persistent/var/lib/sops-nix/key.txt") intentionally live directly
  # on the @persistent subvolume, not through this preservation module.
  # The cleanup-root wipe only replaces @root, so direct /persistent
  # paths survive every boot without a bind-mount entry.
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      commonMountOptions = [
        "x-gvfs-hide"
      ];
      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];
      directories = [
        {
          directory = "/etc/NetworkManager/system-connections";
        }
        {
          directory = "/etc/opt/ivpn";
        }
        # Media stack (/var/lib/transmission|lidarr|navidrome,
        # /var/lib/private/prowlarr), OpenRGB, ollama and acme are
        # Desktop-only and live in desktop/configuration/preservation.nix.
        "/var/lib/bluetooth"
        "/var/lib/iwd"
        "/var/lib/nixos"
        # The daily system.autoUpgrade timer is Persistent=true and stores its
        # last-trigger stamp here; the root wipe would otherwise make a boot
        # after the scheduled time forget the missed run until the next day.
        "/var/lib/systemd/timers"
        # Root is wiped at boot, so without this every `flatpak install` --
        # runtimes, apps, and the flathub remote itself -- is undone by the
        # next reboot. The per-user half is under codebam below.
        "/var/lib/flatpak"
        "/var/lib/sbctl"
        "/var/lib/systemd/coredump"
        "/var/lib/tailscale"
        # Bounded by the journald cap (modules/system/journald.nix:
        # SystemMaxUse = 2G). Unmanaged files here are expected to stay
        # small; watch df on the @persistent subvolume.
        "/var/log"
        {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
          mode = "0700";
        }
      ];
      users = {
        root = {
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
          ];
        };
        codebam = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          files = [
            ".claude.json"
            # KConfig writes a temp file and renames it over the target to
            # save atomically. A file bind mount is a mount point, so that
            # rename fails with EBUSY and KConfig reports it as "Disk full?"
            # even with gigabytes free. KConfig resolves a symlink to its
            # canonical path, so the rename lands inside /persistent and the
            # link survives. Directories below stay bind mounts: renames
            # within a mounted directory are ordinary filesystem operations.
            {
              file = ".config/kwinoutputconfig.json";
              how = "symlink";
              createLinkTarget = true;
            }
            {
              file = ".config/kwalletrc";
              how = "symlink";
              createLinkTarget = true;
            }
            {
              file = ".config/kwalletmanagerrc";
              how = "symlink";
              createLinkTarget = true;
            }
            ".config/viewport/openai-auth.json"
          ];
          directories = [
            {
              directory = ".ssh";
              mode = "0700";
            }
            {
              directory = ".gnupg";
              mode = "0700";
            }
            {
              directory = ".nixops";
              mode = "0700";
            }
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
            "Downloads"
            "Music"
            "Pictures"
            "Documents"
            "Videos"
            "Games"
            # systemd user services
            ".config/systemd/user"
            ".local/share/direnv"
            ".local/share/fish"
            # OpenCode sessions, auth, snapshots, selected model, prompt
            # history, and mutable global plugin/config state.
            ".local/share/opencode"
            ".local/state/opencode"
            ".config/opencode"
            # The v2 desktop client's Electron userData (appData +
            # `ai.opencode.desktop`): drafts.sqlite, window geometry, app
            # settings, the staged opencode2 sidecar, and the shell's own
            # logs. The CLI paths above are shared with it; this directory
            # is desktop-only and a root wipe otherwise loses every draft
            # and the window layout.
            ".config/ai.opencode.desktop"
            # Pi agent settings and plugins
            ".pi"
            # deepseek harness settings and plugins
            ".dsh"
            # `wrangler login` OAuth token. The agentic-inbox email MCP
            # bridge (home/email-mcp.nix, registered in home/agents.nix and
            # home/hermes.nix) reads it on every MCP start; without this a
            # root wipe silently logs the bridge out.
            ".config/.wrangler"
            # Shared agent-memory knowledge graph (the `agent-memory` user
            # service owned by home/agents.nix): one JSONL file, machine-local.
            ".local/share/agent-memory"
            # `flatpak --user install` and the app data those apps write.
            # The system-wide half is /var/lib/flatpak above.
            ".local/share/flatpak"
            {
              directory = ".var";
              mode = "0700";
            }
            {
              directory = ".steam";
              mode = "0700";
            }
            ".tmux"
            {
              directory = ".local/share/Steam";
              mode = "0700";
            }
            ".claude"
            ".config/claude"
            ".config/claude-code"
            ".gemini"
            ".kimi-code"
            ".librewolf"
            ".firedragon"
            ".local/state/wireplumber"
            ".local/state/mpv"
            ".config/mprisence"
            ".config/Antigravity"
            ".config/vesktop"
            ".config/equibop"
            ".config/Element"
            ".config/discord"
            ".config/discordcanary"
            ".config/discordptb"
            ".config/polariumcode"
            ".local/share/TelegramDesktop"
            ".local/share/zoxide"
            ".config/YouTube Music Desktop App"
            ".config/mnw"
            ".local/share/PrismLauncher"
            ".local/share/mnw"
            {
              directory = ".local/share/containers";
              mode = "0700";
            }
            # podman quadlets (e.g. flaresolverr.container) live here; without
            # this a root wipe drops the unit and rootless podman has no quadlet
            {
              directory = ".config/containers";
              mode = "0700";
            }
            ".config/OpenRGB"
            # obs-studio scenes, profiles and the plugin settings under
            # plugin_config; nothing in it is generated by the home-manager
            # module, so a root wipe loses every scene collection.
            ".config/obs-studio"
            ".config/heroic"
            ".config/nushell"
            ".config/qmk"
            ".cache/nix-index"
            ".config/github-copilot"
            # hermes-desktop CEF user-data (window-state, theme, preferences,
            # desktop-installation.json). HERMES_HOME itself is preserved as
            # .hermes in desktop/configuration/preservation.nix.
            ".config/Hermes"
            {
              directory = ".config/gh";
              mode = "0700";
            }
            ".config/gcloud"
            ".local/share/steel"
            ".config/retroarch"
            {
              directory = ".config/chromium";
              mode = "0700";
            }
            ".config/mozilla"
            {
              directory = ".config/google-chrome";
              mode = "0700";
            }
            {
              directory = ".config/google-chrome-unstable";
              mode = "0700";
            }
            ".local/share/vkBasalt/shaders"
            ".local/share/kwalletd"
            ".local/share/uv"
            ".local/bin"
            # SigmaShake Desktop: license, prefs, daemon state. Not generated
            # by the flake; a root wipe would drop the login.
            ".sigmashake"
          ];
        };
      };
    };
  };

  systemd.tmpfiles.settings.preservation = {
    "/home/codebam/Videos/Anime".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    # Only Pictures itself is preserved; grim writes into this subdirectory and
    # fails silently if it is missing after a root wipe.
    "/home/codebam/Pictures/Screenshots".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
  };

  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };
}
