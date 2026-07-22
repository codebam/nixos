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
          directory = "/var/cache/ccache";
          user = "root";
          group = "nixbld";
        }
        "/etc/NetworkManager/system-connections"
        "/etc/mullvad-vpn"
        "/etc/opt/ivpn"
        "/var/lib/OpenRGB"
        "/var/lib/transmission"
        {
          directory = "/var/lib/lidarr";
          user = "lidarr";
          group = "lidarr";
        }
        "/var/lib/navidrome"
        "/var/lib/private/prowlarr"
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
          user = "ollama";
          group = "ollama";
        }
        {
          directory = "/var/lib/private/open-webui";
          user = "open-webui";
          group = "open-webui";
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
          files = [
            ".config/kwinoutputconfig.json"
            ".config/kwalletrc"
            ".config/kwalletmanagerrc"
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
            ".firedragon"
            ".password-store"
            ".local/state/wireplumber"
            ".config/mprisence"
            ".config/Antigravity"
            ".config/vesktop"
            ".config/equibop"
            ".config/Element"
            ".config/discord"
            ".config/discordcanary"
            ".config/discordptb"
            ".config/in.cinny.app"
            ".local/share/TelegramDesktop"
            ".local/share/bolt-launcher"
            ".local/share/zoxide"
            ".config/YouTube Music Desktop App"
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
            ".config/supersonic"
            ".config/feishin"
            ".local/share/steel"
            ".config/calcurse"
            ".local/share/calcurse"
            ".config/retroarch"
            ".config/chromium"
            ".config/mozilla"
            ".config/google-chrome"
            ".config/google-chrome-unstable"
            ".config/agy-sandbox"
            ".local/share/vkBasalt/shaders"
            ".local/share/kwalletd"
            ".local/share/iamb"
            ".cache/iamb"
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
