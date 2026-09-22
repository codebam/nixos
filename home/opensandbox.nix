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
  config,
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

  # The OpenSandbox-backed shell opencode2's `shell` setting points at; see
  # home/opencode-sandbox-shell.nix. Imported here too so the command is on
  # PATH for a human debugging a sandboxed command by hand.
  opencodeSandboxShell = import ./opencode-sandbox-shell.nix { inherit pkgs lib; };
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

  # All OpenSandbox containers share this user slice, and its MemoryMax keeps
  # the whole platform below 80% of host RAM. The lifecycle server container
  # joins through --cgroup-parent in ExecStart and the sandboxes it creates
  # join through the sitecustomize patch below; see the comment on
  # serverSitecustomize for why both sides are needed.
  containerSlice = "opensandbox.slice";
  containerMemoryMax = "80%";
  containerMemoryHigh = "70%";
  containerMemorySwapMax = "2G";
  containerCpuQuota = "800%";
  containerCpuWeight = 50;
  containerTasksMax = 16384;
  containerIoWeight = 50;

  # Per-sandbox resource defaults and maxima, applied inside the server by the
  # sitecustomize patch. These are byte/nano-CPU values because that is what
  # the Docker API takes; the SDK's own defaults are cpu=1/memory=2Gi, so the
  # defaults here only matter for raw API clients and the maxima stop a single
  # sandbox from consuming the whole 80% slice. dsh requests cpu=4/memory=8Gi,
  # which stays below both maxima.
  sandboxDefaultCpuNano = 1000000000;
  sandboxDefaultMemoryBytes = 2147483648;
  sandboxMaxCpuNano = 8000000000;
  sandboxMaxMemoryBytes = 17179869184;
  sandboxMaxGpu = 1;

  # Host paths that are always mounted read-only regardless of what a create
  # request asks for: immutable inputs (/nix/store), host control sockets, and
  # credentials. The same list doubles as the server-side ancestor guard: a
  # bind whose source directory *contains* one of these paths is rejected
  # outright, so the old `workdir=/home/codebam` bypass cannot mount the whole
  # home directory around the read-only guard. Defined once in
  # opensandbox-paths.nix because the dsh plugin's ctx.fs fence consumes it too.
  sandboxReadonlyHostPaths =
    (import ./opensandbox-paths.nix { home = config.home.homeDirectory; }).readonlyHostPaths;

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
        # A requested TTL may not exceed 24h; osb-work defaults to 8h and dsh
        # to 12h. A request with no timeout gets the SDK default (10m), but an
        # explicit `timeout = null` (osb --timeout none) still means manual
        # cleanup and bypasses this cap.
        printf '%s\n' 'max_sandbox_timeout_seconds = 86400'
        # Local single-user backpressure settings; upstream defaults are 1024
        # concurrent connections / 200 thread-pool workers / 2048 backlog.
        printf '%s\n' 'limit_concurrency = 128'
        printf '%s\n' 'thread_pool_size = 64'
        printf '%s\n' 'backlog = 256'
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
        printf '%s\n' '# these prefixes. The prefix list is deliberately broad because dsh'
        printf '%s\n' '# workspaces and explicit /directory-add grants can name any project'
        printf '%s\n' '# directory; sitecustomize.py adds the real control: a bind whose source'
        printf '%s\n' '# contains a protected credential/control path (SandboxReadonlyHostPaths)'
        printf '%s\n' '# is rejected, and a bind exactly on one is forced read-only.'
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

  # Fixes the pinned server image cannot carry itself, applied outside it
  # rather than by rebuilding the image:
  #
  # 1. Podman's archive API cannot consume the trailing record padding Python's
  #    stdlib tarfile writes. It reads tar's two EOF blocks and exits while the
  #    server is still writing the rest of the 10 KiB record, so
  #    `PUT /containers/{id}/archive` intermittently -- and with other sandboxes
  #    running, reliably -- answers 500 "passing bulk input to subprocess:
  #    write |1: broken pipe". The lifecycle server surfaces that as
  #    SANDBOX_EXECD_DISTRIBUTION_FAILED, so every new sandbox create fails
  #    while already-running sandboxes keep working. The patch trims each
  #    put_archive body back to the second EOF block, which is exactly what a
  #    512-byte-record tar emits; testcontainers ships the same fix as
  #    blockFactor=1 (testcontainers-dotnet#1683 / #1684).
  #
  # 2. Every OpenSandbox container must live inside one memory cgroup: for
  #    containerSlice, containerMemoryMax caps the lot -- the lifecycle server
  #    and every sandbox it creates. Rootless podman puts containers under the
  #    nested default `user.slice`, not under podman.service, and neither
  #    containers.conf nor the lifecycle API has a server-wide cgroup-parent
  #    setting. The only lever is each create request's HostConfig.CgroupParent,
  #    so the patch adds it there; ExecStart passes the same parent for the
  #    server container itself.
  #
  # 3. Per-sandbox guardrails: raw API clients can omit or overstate
  #    resourceLimits, ask for the bwrap isolation extension, or request a
  #    Windows profile. The patch fills in conservative CPU/memory defaults,
  #    clamps a single sandbox below the maxima passed in the environment, and
  #    rejects the two optional profiles unless explicitly enabled.
  #
  # 4. Sensitive host paths (/nix/store, /etc/nix, /nix/var/nix, agent
  #    sockets/keyrings, dotfiles that hold credentials) are forced read-only,
  #    and any bind whose source directory contains one of them is rejected.
  #    The old guard only checked descendants, so mounting a parent such as
  #    /home/codebam turned the sensitive read-only children into ordinary
  #    writable paths inside the container.
  serverSitecustomize = pkgs.writeTextDir "sitecustomize.py" ''
    """Apply OpenSandbox server guardrails at interpreter startup.

    The pinned server image is used unchanged; everything here is a targeted
    runtime patch: Podman tar-record trimming, cgroup-parent injection,
    per-sandbox resource defaults/clamps, sensitive-mount read-only enforcement,
    and rejection of Windows/bwrap-isolation requests unless enabled.
    """

    import os
    import sys

    _BLOCK = 512
    _ZERO = bytes(_BLOCK)
    _CGROUP_PARENT = "${containerSlice}"


    def _env_int(name, default):
        try:
            return int(os.environ.get(name, ""))
        except ValueError:
            return default


    _DEFAULT_CPU_NANO = _env_int("OPENSANDBOX_DEFAULT_SANDBOX_CPU_NANO", 1000000000)
    _DEFAULT_MEMORY = _env_int("OPENSANDBOX_DEFAULT_SANDBOX_MEMORY_BYTES", 2147483648)
    _MAX_CPU_NANO = _env_int("OPENSANDBOX_MAX_SANDBOX_CPU_NANO", 8000000000)
    _MAX_MEMORY = _env_int("OPENSANDBOX_MAX_SANDBOX_MEMORY_BYTES", 17179869184)
    _MAX_GPU = _env_int("OPENSANDBOX_MAX_SANDBOX_GPU", 1)
    _READONLY_HOST_PATHS = [
        os.path.realpath(path)
        for path in os.environ.get("OPENSANDBOX_READONLY_HOST_PATHS", "").split(":")
        if path
    ]
    _ALLOW_ISOLATION_EXTENSION = (
        os.environ.get("OPENSANDBOX_ALLOW_ISOLATION_EXTENSION", "0") == "1"
    )
    _ALLOW_WINDOWS_PROFILE = (
        os.environ.get("OPENSANDBOX_ALLOW_WINDOWS_PROFILE", "0") == "1"
    )


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


    def _install_cgroup_parent():
        try:
            from docker.api.container import ContainerApiMixin
        except Exception:
            return

        original = getattr(ContainerApiMixin, "create_container", None)
        if original is None or getattr(original, "_opensandbox_cgroup_parent", False):
            return

        def create_container(self, *args, **kwargs):
            # OpenSandbox always passes host_config by keyword; leave calls that
            # do not carry one alone rather than inventing a host config.
            host_config = kwargs.get("host_config")
            if isinstance(host_config, dict):
                host_config.setdefault("CgroupParent", _CGROUP_PARENT)
            return original(self, *args, **kwargs)

        create_container._opensandbox_cgroup_parent = True
        ContainerApiMixin.create_container = create_container
        import sys

        print(
            "opensandbox-cgroup-parent: confining containers to " + _CGROUP_PARENT,
            file=sys.stderr,
        )


    def _install_resource_limits():
        try:
            from opensandbox_server.services.docker.container_ops import DockerContainerOpsMixin
        except Exception:
            return

        original = getattr(DockerContainerOpsMixin, "_resolve_resource_limits", None)
        if original is None or getattr(original, "_opensandbox_resource_limits", False):
            return

        def resolve_resource_limits(self, request):
            mem_limit, nano_cpus, gpu_count = original(self, request)
            clamped = []

            if mem_limit is None or mem_limit <= 0:
                mem_limit = _DEFAULT_MEMORY
            elif _MAX_MEMORY > 0 and mem_limit > _MAX_MEMORY:
                mem_limit = _MAX_MEMORY
                clamped.append("memory")

            if nano_cpus is None or nano_cpus <= 0:
                nano_cpus = _DEFAULT_CPU_NANO
            elif _MAX_CPU_NANO > 0 and nano_cpus > _MAX_CPU_NANO:
                nano_cpus = _MAX_CPU_NANO
                clamped.append("cpu")

            if gpu_count is not None and _MAX_GPU >= 0 and gpu_count > _MAX_GPU:
                gpu_count = _MAX_GPU
                clamped.append("gpu")

            if clamped:
                import sys

                print(
                    "opensandbox-resource-limit: clamped "
                    + ", ".join(clamped)
                    + " for one sandbox",
                    file=sys.stderr,
                )
            return mem_limit, nano_cpus, gpu_count

        resolve_resource_limits._opensandbox_resource_limits = True
        DockerContainerOpsMixin._resolve_resource_limits = resolve_resource_limits
        print(
            "opensandbox-resource-limit: per-sandbox defaults and maxima installed",
            file=sys.stderr,
        )


    def _install_volume_guard():
        try:
            from opensandbox_server.services.docker.volumes import DockerVolumesMixin
        except Exception:
            return

        original = getattr(DockerVolumesMixin, "_build_volume_binds", None)
        if original is None or getattr(original, "_opensandbox_volume_guard", False):
            return

        def host_is_sensitive(path):
            try:
                resolved = os.path.realpath(path)
            except Exception:
                return False
            for prefix in _READONLY_HOST_PATHS:
                if resolved == prefix or resolved.startswith(prefix + os.sep):
                    return True
            return False

        def host_contains_protected(path):
            """Return the protected descendant when `path` is its ancestor."""
            try:
                resolved = os.path.realpath(path)
            except Exception:
                return None
            if resolved == os.sep:
                return os.sep
            for prefix in _READONLY_HOST_PATHS:
                if prefix != resolved and prefix.startswith(resolved + os.sep):
                    return prefix
            return None

        def build_volume_binds(self, volumes, pvc_inspect_cache=None):
            binds = original(self, volumes, pvc_inspect_cache)
            guarded = []
            for bind in binds:
                parts = bind.rsplit(":", 2)
                if len(parts) == 3 and os.path.isabs(parts[0]):
                    protected = host_contains_protected(parts[0])
                    if protected is not None:
                        raise ValueError(
                            "refusing to bind "
                            + parts[0]
                            + ": it contains the protected host path "
                            + protected
                            + "; bind that path directly if it is needed"
                        )
                    if host_is_sensitive(parts[0]):
                        options = [part for part in parts[2].split(",") if part]
                        options = ["ro" if part == "rw" else part for part in options]
                        if "ro" not in options:
                            options.append("ro")
                        bind = ":".join([parts[0], parts[1], ",".join(options)])
                guarded.append(bind)
            return guarded

        build_volume_binds._opensandbox_volume_guard = True
        DockerVolumesMixin._build_volume_binds = build_volume_binds
        print(
            "opensandbox-volume-guard: sensitive host paths are read-only",
            file=sys.stderr,
        )


    def _install_provision_guards():
        try:
            from opensandbox_server.services.docker.docker_service import DockerSandboxService
        except Exception:
            return

        original = getattr(DockerSandboxService, "_provision_sandbox", None)
        if original is None or getattr(original, "_opensandbox_provision_guards", False):
            return

        def provision_sandbox(self, *args, **kwargs):
            request = kwargs.get("request")
            if request is None and len(args) > 1:
                request = args[1]

            if request is not None:
                platform = getattr(request, "platform", None)
                if (
                    not _ALLOW_WINDOWS_PROFILE
                    and getattr(platform, "os", None) == "windows"
                ):
                    raise ValueError(
                        "Windows-profile sandboxes are disabled on this host; "
                        "set OPENSANDBOX_ALLOW_WINDOWS_PROFILE=1 to allow them."
                    )

                extensions = getattr(request, "extensions", None) or {}
                if (
                    not _ALLOW_ISOLATION_EXTENSION
                    and extensions.get("bootstrap.execd.isolation") == "enable"
                ):
                    raise ValueError(
                        "The bwrap isolation extension is disabled on this host; "
                        "set OPENSANDBOX_ALLOW_ISOLATION_EXTENSION=1 to allow it."
                    )

            return original(self, *args, **kwargs)

        provision_sandbox._opensandbox_provision_guards = True
        DockerSandboxService._provision_sandbox = provision_sandbox
        print(
            "opensandbox-provision-guard: Windows and bwrap-isolation requests are disabled",
            file=sys.stderr,
        )


    _install()
    _install_cgroup_parent()
    _install_resource_limits()
    _install_volume_guard()
    _install_provision_guards()
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
    opencodeSandboxShell
  ];

  # The sandbox server only makes sense where rootless podman exists: desktop
  # and laptop (desktop-laptop/configuration/virtualisation.nix); the Steam
  # Deck has neither podman nor the service, and the wrappers there still fall
  # back to OPEN_SANDBOX_DOMAIN/a config file for a remote server.
  # Bound the rootless podman logs as well as OpenSandbox's slice: Podman's
  # default k8s-file driver has no per-container size limit, so a chatty
  # sandbox could otherwise grow ~/.local/share/containers without bound.
  # Home Manager's podman module owns ~/.config/containers/containers.conf, so
  # this merges the cap into that generated file (rootless podman only).
  services.podman.settings.containers = lib.mkIf podmanEnabled {
    containers.log_size_max = 16777216;
  };

  systemd.user = {
    slices = lib.mkIf podmanEnabled {
      opensandbox = {
        Unit.Description = "OpenSandbox CPU/memory/process budget";
        Slice = {
          CPUAccounting = true;
          IOAccounting = true;
          MemoryAccounting = true;
          MemoryHigh = containerMemoryHigh;
          MemoryMax = containerMemoryMax;
          MemorySwapMax = containerMemorySwapMax;
          CPUQuota = containerCpuQuota;
          CPUWeight = containerCpuWeight;
          TasksMax = containerTasksMax;
          IOWeight = containerIoWeight;
        };
        # Starting the slice with the user manager is not required for it to be
        # used (a container scope pulls it in), but it keeps the budget in place
        # before the first sandbox.
        Install.WantedBy = [ "default.target" ];
      };
    };

    timers = lib.mkIf podmanEnabled {
      opensandbox-image-prune = {
        Unit.Description = "Monthly reclaim of the rootless podman image cache";
        Timer = {
          # Only unused images older than 30 days are removed; images backing a
          # stopped-but-existing sandbox container are kept, and removed
          # work-type images are re-pulled on next use.
          OnCalendar = "monthly";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };

    services = lib.mkIf podmanEnabled {
      opensandbox-image-prune = {
        Unit = {
          Description = "Prune unused rootless podman images older than 30 days";
          # Nothing to prune before the first rootless container storage exists.
          ConditionPathExists = "%h/.local/share/containers";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.podman}/bin/podman image prune -a -f --filter until=720h";
        };
      };

      opensandbox-server = {
        Unit = {
          Description = "OpenSandbox sandbox lifecycle server (rootless podman)";
          # Requiring the slice ensures its MemoryMax is active before podman
          # starts the server container; depending only on the per-create
          # CgroupParent would let systemd synthesize an unlimited implicit
          # slice if the configured unit were ever missing.
          After = [
            "podman.socket"
            containerSlice
          ];
          Requires = [
            "podman.socket"
            containerSlice
          ];
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
            "--cgroup-parent=${containerSlice}"
            "--env SANDBOX_CONFIG_PATH=/etc/opensandbox/config.toml"
            "--env DOCKER_HOST=unix:///var/run/docker.sock"
            "--volume %t/podman/podman.sock:/var/run/docker.sock"
            "--volume ${configPath}:/etc/opensandbox/config.toml:ro"
            "--volume %h/.local/state/opensandbox:/root/.opensandbox"
            # See serverSitecustomize: the tar trim keeps sandbox creation from
            # failing on padded uploads, the cgroup-parent patch keeps every
            # container it creates inside the shared resource slice, and the
            # remaining patches apply per-sandbox resource defaults/clamps,
            # read-only sensitive mounts, and Windows/bwrap guardrails.
            "--env PYTHONPATH=/opt/opensandbox-sitecustomize"
            "--volume ${serverSitecustomize}:/opt/opensandbox-sitecustomize:ro"
            "--env OPENSANDBOX_DEFAULT_SANDBOX_CPU_NANO=${toString sandboxDefaultCpuNano}"
            "--env OPENSANDBOX_DEFAULT_SANDBOX_MEMORY_BYTES=${toString sandboxDefaultMemoryBytes}"
            "--env OPENSANDBOX_MAX_SANDBOX_CPU_NANO=${toString sandboxMaxCpuNano}"
            "--env OPENSANDBOX_MAX_SANDBOX_MEMORY_BYTES=${toString sandboxMaxMemoryBytes}"
            "--env OPENSANDBOX_MAX_SANDBOX_GPU=${toString sandboxMaxGpu}"
            "--env OPENSANDBOX_READONLY_HOST_PATHS=${lib.concatStringsSep ":" sandboxReadonlyHostPaths}"
            "--env OPENSANDBOX_ALLOW_ISOLATION_EXTENSION=0"
            "--env OPENSANDBOX_ALLOW_WINDOWS_PROFILE=0"
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
  };
}
