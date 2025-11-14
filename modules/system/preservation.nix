_: {
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
          how = "symlink";
        }
      ];
      directories = [
        {
          directory = "/etc/nixos";
          user = "codebam";
          group = "users";
        }
        {
          directory = "/var/cache/ccache";
          user = "root";
          group = "nixbld";
        }
        "/etc/NetworkManager/system-connections"
        "/etc/ssh"
        "/etc/mullvad-vpn"
        "/var/lib/OpenRGB"
        "/var/lib/bluetooth"
        "/var/lib/iwd"
        "/var/lib/nixos"
        "/var/lib/sbctl"
        "/var/lib/systemd/coredump"
        "/var/lib/tailscale"
        "/var/log"
        {
          directory = "/var/lib/colord";
          user = "colord";
          group = "colord";
          mode = "0700";
        }
        {
          directory = "/var/lib/private/ollama";
          user = "nobody";
          group = "nogroup";
        }
        {
          directory = "/var/lib/private/open-webui";
          user = "nobody";
          group = "nogroup";
        }
        {
          directory = "/var/lib/acme";
          user = "acme";
          group = "nginx";
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
            ".local/share/direnv"
            ".local/share/fish"
            ".steam"
            ".tmux"
            ".local/share/Steam"
            ".claude"
            ".gemini"
            ".librewolf"
            ".password-store"
            ".local/state/wireplumber"
            ".config/Element"
            ".config/discord"
            ".local/share/TelegramDesktop"
            ".local/share/zoxide"
            ".config/YouTube Music"
            ".config/mnw"
            ".local/share/PrismLauncher"
            ".local/share/mnw"
            ".local/share/containers"
            ".config/OpenRGB"
            ".config/heroic"
            ".config/nushell"
            ".config/qmk"
            ".cache/nix-index"
            ".config/github-copilot"
            ".config/gcloud"
            ".config/lsfg-vk"
            ".local/share/steel"
            ".config/calcurse"
            ".local/share/calcurse"
            ".config/retroarch"
          ];
        };
      };
    };
  };
  systemd.tmpfiles.settings.preservation = {
    "/home/codebam/.config".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local/share".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.local/state".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
    "/home/codebam/.cache".d = {
      user = "codebam";
      group = "users";
      mode = "0755";
    };
  };

  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };
}
