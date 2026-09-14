# OpenSandbox: the Docker/Podman sandbox platform that replaces the old
# nono Landlock profiles for per-work-type isolation. The server runs as a
# rootless podman container in the user session, sandboxes are created on the
# same rootless podman instance through the mounted socket, and the CLI/MCP
# wrappers inject the per-boot API key the server generates.
#
# Why a user service rather than virtualisation.oci-containers: the server
# controls the container runtime through the socket it mounts. Running it
# rootless means that socket and every sandbox it creates stay in codebam's
# user namespace, so a compromised lifecycle server cannot become root on the
# host; rootful podman (the flaresolverr pattern) would hand it that.
{
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  # The per-work-type catalog and `osb-work` helper live in their own file so
  # the image table can be read without the service/wrapper plumbing.
  work = import ./opensandbox-work.nix { inherit pkgs lib; };
  inherit (work) osbWork;
  # Keep port_range_min/max in sync with the loopback-only nftables guard in
  # modules/system/networking.nix.
  serverPort = 8090;
  sandboxPortMin = 40000;
  sandboxPortMax = 40200;

  # Pinned by manifest digest; the tags are in comments because podman (like
  # docker) should be handed a digest-only reference so a moved tag cannot
  # change what this host executes.
  serverImage = "docker.io/opensandbox/server@sha256:ae8dfbb277f40a39ff01ef35e5e1c10675acfe0fa9db15259b8f323e5efab778";
  execdImage = "docker.io/opensandbox/execd@sha256:6cf7dba2f21f0b536e100563d841ac58a9f31c2b0a081b7ac76796a24d6f47e2";

  # A named network rather than "bridge": rootless podman's default network is
  # the pasta-backed "podman" network, while OpenSandbox treats any non-host
  # name as a user-defined bridge and resolves published ports through it.
  # Network policies/egress require the literal "bridge" network and are not
  # configured here; switch this value if you need them.
  sandboxNetwork = "opensandbox";

  # The server config holds the API key, so it is generated under the user's
  # runtime dir (tmpfs, mode 0600) on every boot rather than stored in the Nix
  # store or SOPS. The CLI/MCP wrappers read the same file.
  runtimeDir = "%t/opensandbox";
  configPath = "${runtimeDir}/sandbox.toml";

  serverPrepare = pkgs.writeShellApplication {
    name = "opensandbox-server-prepare";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
            set -eu
            : "''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
            config_dir="$XDG_RUNTIME_DIR/opensandbox"
            state_dir="$HOME/.local/state/opensandbox"
            install -d -m 0700 "$config_dir" "$state_dir"

            key_file="$config_dir/api-key"
            if [ ! -s "$key_file" ]; then
              umask 077
              head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$key_file"
            fi
            key="$(cat "$key_file")"

            # Generated with printf rather than a heredoc: nixfmt re-indents the
      # text block, and an indented heredoc terminator would no longer end the
      # heredoc.
      {
        printf '%s\n' '[server]'
        printf '%s\n' 'host = "127.0.0.1"'
        printf '%s\n' "port = ${toString serverPort}"
        printf '%s\n' "api_key = \"$key\""
        printf '\n'
        printf '%s\n' '[proxy]'
        printf '%s\n' '# Sandboxes live on a rootless bridge network the server cannot route to,'
        printf '%s\n' '# so the server-side proxy talks to their host-published ports on loopback.'
        printf '%s\n' 'resolve_internal = false'
        printf '\n'
        printf '%s\n' '[log]'
        printf '%s\n' 'level = "INFO"'
        printf '\n'
        printf '%s\n' '[runtime]'
        printf '%s\n' 'type = "docker"'
        printf '%s\n' "execd_image = \"${execdImage}\""
        printf '\n'
        printf '%s\n' '[docker]'
        printf '%s\n' "network_mode = \"${sandboxNetwork}\""
        printf '%s\n' 'host_ip = "127.0.0.1"'
        printf '%s\n' "port_range_min = ${toString sandboxPortMin}"
        printf '%s\n' "port_range_max = ${toString sandboxPortMax}"
        printf '%s\n' 'pids_limit = 4096'
        # Multi-GB sandbox images can outlive the SDK's 180s default; give
        # the server's Docker API calls room to finish a cold pull.
        printf '%s\n' 'api_timeout = 1800'
        printf '\n'
        printf '%s\n' '[storage]'
        printf '%s\n' '# Host bind mounts are rejected unless their source path is under one of'
        printf '%s\n' '# these prefixes: /home covers project dirs, /persistent the system flake,'
        printf '%s\n' '# /tmp scratch work, and /nix/store the read-only toolchain mount.'
        printf '%s\n' 'allowed_host_paths = ["/home/codebam", "/persistent", "/tmp", "/nix/store"]'
        printf '\n'
        printf '%s\n' '[store]'
        printf '%s\n' '# Mounted from ~/.local/state/opensandbox so sandbox records survive a'
        printf '%s\n' '# reboot while their podman storage does (modules/system/preservation.nix).'
        printf '%s\n' 'path = "/root/.opensandbox/opensandbox.db"'
      } > "$config_dir/sandbox.toml"
            chmod 600 "$config_dir/sandbox.toml"
    '';
  };

  networkEnsure = pkgs.writeShellApplication {
    name = "opensandbox-network";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      set -eu
      if ! podman network inspect ${sandboxNetwork} >/dev/null 2>&1; then
        podman network create ${sandboxNetwork}
      fi
    '';
  };

  # The raw CLI/MCP binaries know nothing about the generated key. Wrapping
  # instead of writing a config file keeps the key out of a second on-disk
  # location and makes `osb config show` reflect the wrapper's connection.
  mkClientWrapper =
    {
      name,
      package,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        package
      ];
      text = ''
        set -eu
        runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        key_file="$runtime_dir/opensandbox/api-key"
        if [ -z "''${OPEN_SANDBOX_API_KEY:-}" ] && [ -r "$key_file" ]; then
          OPEN_SANDBOX_API_KEY="$(cat "$key_file")"
          export OPEN_SANDBOX_API_KEY
        fi
        if [ -z "''${OPEN_SANDBOX_DOMAIN:-}" ]; then
          OPEN_SANDBOX_DOMAIN="127.0.0.1:${toString serverPort}"
          export OPEN_SANDBOX_DOMAIN
        fi
        # A create request can include a multi-GB image pull; the SDK/CLI
        # default of 30s would abort it. The server's own Docker API timeout
        # (api_timeout in the generated config) is the real upper bound.
        if [ -z "''${OPEN_SANDBOX_REQUEST_TIMEOUT:-}" ]; then
          OPEN_SANDBOX_REQUEST_TIMEOUT="900"
          export OPEN_SANDBOX_REQUEST_TIMEOUT
        fi
        exec ${lib.getExe package} "$@"
      '';
    };

  osb = mkClientWrapper {
    name = "osb";
    package = pkgs.opensandbox-cli;
  };

  opensandboxMcp = mkClientWrapper {
    name = "opensandbox-mcp";
    package = pkgs.opensandbox-mcp;
  };

  podmanEnabled = osConfig.virtualisation.podman.enable or false;
in
{
  home.packages = [
    osb
    opensandboxMcp
    osbWork
  ];

  # The sandbox server only makes sense where rootless podman exists: desktop
  # and laptop (desktop-laptop/configuration/virtualisation.nix); the Steam
  # Deck has neither podman nor the service, and the wrappers there still fall
  # back to OPEN_SANDBOX_DOMAIN/a config file for a remote server.
  systemd.user.services = lib.mkIf podmanEnabled {
    opensandbox-server = {
      Unit = {
        Description = "OpenSandbox sandbox lifecycle server (rootless podman)";
        After = [ "podman.socket" ];
        Requires = [ "podman.socket" ];
        # Pulling the server image can exceed the default 90s start limit on a
        # cold cache; don't let systemd kill a healthy pull.
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStartPre = [
          (lib.getExe serverPrepare)
          (lib.getExe networkEnsure)
        ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.podman}/bin/podman run"
          "--rm"
          "--replace"
          "--name opensandbox-server"
          "--network=host"
          "--env SANDBOX_CONFIG_PATH=/etc/opensandbox/config.toml"
          "--env DOCKER_HOST=unix:///var/run/docker.sock"
          "--volume %t/podman/podman.sock:/var/run/docker.sock"
          "--volume ${configPath}:/etc/opensandbox/config.toml:ro"
          "--volume %h/.local/state/opensandbox:/root/.opensandbox"
          serverImage
        ];
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 600;
        TimeoutStopSec = 60;
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
