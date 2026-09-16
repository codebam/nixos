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
        printf '%s\n' '# /tmp scratch work, /nix/store the read-only toolchain mount, and the'
        printf '%s\n' '# last three what the dsh container world needs to be a workspace rather'
        printf '%s\n' '# than only a boundary: the nix client config and the daemon socket (its'
        printf '%s\n' '# builds go through the host daemon) plus the gpg agent sockets (commit'
        printf '%s\n' '# signing and SSH push through the YubiKey).'
        printf '%s\n' 'allowed_host_paths = ["/home/codebam", "/persistent", "/tmp", "/nix/store", "/etc/nix", "/nix/var/nix", "/run/user/1000/gnupg"]'
        printf '\n'
        printf '%s\n' '[store]'
        printf '%s\n' '# Mounted from ~/.local/state/opensandbox so sandbox records survive a'
        printf '%s\n' '# reboot while their podman storage does (modules/system/preservation.nix).'
        printf '%s\n' 'path = "/root/.opensandbox/opensandbox.db"'
      } > "$config_dir/sandbox.toml"
            chmod 600 "$config_dir/sandbox.toml"
    '';
  };

  # Podman's archive API cannot consume the trailing record padding Python's
  # stdlib tarfile writes. It reads tar's two EOF blocks and exits while the
  # server is still writing the rest of the 10 KiB record, so
  # `PUT /containers/{id}/archive` intermittently -- and with other sandboxes
  # running, reliably -- answers 500 "passing bulk input to subprocess:
  # write |1: broken pipe". The lifecycle server surfaces that as
  # SANDBOX_EXECD_DISTRIBUTION_FAILED, so every new sandbox create fails while
  # already-running sandboxes keep working. This sitecustomize trims each
  # put_archive body back to the second EOF block, which is exactly what a
  # 512-byte-record tar emits; testcontainers ships the same fix as
  # blockFactor=1 (testcontainers-dotnet#1683 / #1684).
  serverTarPadFix = pkgs.writeTextDir "sitecustomize.py" ''
    """Trim tar record padding before docker-py sends an archive to Podman.

    The OpenSandbox Docker runtime builds archives with the stdlib tarfile
    default record size (10 KiB). Podman's archive handler exits at the two
    zero EOF blocks, so any padding written afterwards breaks the HTTP pipe
    with a 500 and the sandbox create fails. Rewriting each body to end at
    that EOF marker is byte-for-byte what tarfile emits with a 512-byte
    record. Archives with any other shape are passed through untouched.
    """

    _BLOCK = 512
    _ZERO = bytes(_BLOCK)


    def _logical_end(archive):
        pos = 0
        total = len(archive)
        while pos + _BLOCK <= total:
            if archive[pos:pos + _BLOCK] == _ZERO:
                if archive[pos + _BLOCK:pos + 2 * _BLOCK] == _ZERO:
                    return pos + 2 * _BLOCK
                return None
            field = archive[pos + 124:pos + 136].split(b"\0", 1)[0].strip()
            try:
                size = int(field or b"0", 8)
            except ValueError:
                return None
            pos += _BLOCK + ((size + _BLOCK - 1) // _BLOCK) * _BLOCK
        return None


    def _trim(data):
        archive = bytes(data)
        end = _logical_end(archive)
        if end is None or end >= len(archive) or archive[end:].strip(b"\0"):
            return data
        return archive[:end]


    def _wrap(original, high_level):
        # A factory, not an inline closure: both branches would otherwise share
        # one late-bound `original` and the api wrapper would end up calling the
        # model method (four positional arguments).
        if high_level:

            def put_archive(self, path, data=None):
                if data is None:
                    return original(self, path)
                return original(self, path, _trim(data))

        else:

            def put_archive(self, container, path, data):
                return original(self, container, path, _trim(data))

        put_archive._opensandbox_tar_trim = True
        return put_archive


    def _install():
        patched = []
        try:
            from docker.api.container import ContainerApiMixin
        except Exception:
            ContainerApiMixin = None
        try:
            from docker.models.containers import Container
        except Exception:
            Container = None

        if ContainerApiMixin is not None:
            original = getattr(ContainerApiMixin, "put_archive", None)
            if original is not None and not getattr(original, "_opensandbox_tar_trim", False):
                ContainerApiMixin.put_archive = _wrap(original, False)
                patched.append("api")

        if Container is not None:
            original = getattr(Container, "put_archive", None)
            if original is not None and not getattr(original, "_opensandbox_tar_trim", False):
                Container.put_archive = _wrap(original, True)
                patched.append("model")

        if patched:
            import sys

            print(
                "opensandbox-tar-pad-fix: trimming put_archive to the tar EOF marker",
                file=sys.stderr,
            )


    _install()
  '';

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
          # See serverTarPadFix: without it Podman rejects the padded tar
          # uploads and no new sandbox can be created.
          "--env PYTHONPATH=/opt/opensandbox-tar-pad-fix"
          "--volume ${serverTarPadFix}:/opt/opensandbox-tar-pad-fix:ro"
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
