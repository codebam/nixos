# The OpenSandbox-backed shell for opencode2.
#
# opencode2's global config points its `shell` setting at this executable, so
# the agent's shell tool runs `<shell> -c <command>` with the session directory
# as cwd and every command executes inside an OpenSandbox container instead of
# the host user's shell -- the same untrusted-agent tier as dsh's default
# world: the workspace is bind-mounted read-write at its own host path,
# /nix/store is mounted read-only so host toolchains resolve, and the container
# gets no Nix daemon, no credentials, and an ephemeral /root.
#
# The sandbox is keyed by workspace root (the git toplevel when the command
# runs inside a repository) and reused until the server's TTL reaps it, so a
# session pays the container start once. `OPENCODE2_NO_SANDBOX=1` in the
# launching environment is the per-process escape hatch back to the host shell,
# mirroring dsh's DSH_NO_OPENSANDBOX.
#
# Interactive invocations (the TUI terminal opens the shell without -c) fall
# back to the host shell: the contract here is command execution, not a PTY
# inside the container.
{
  pkgs,
  lib,
}:

let
  # The pinned Debian image from the per-work-type catalog, so the digest still
  # lives in exactly one place; the `shell` type is the closest fit (minimal
  # POSIX userland, no language runtime).
  work = import ./opensandbox-work.nix { inherit pkgs lib; };
in
pkgs.writers.writePython3Bin "opencode-sandbox-shell"
  {
    libraries = [ pkgs.opensandbox ];
    # Build-time store paths (image, git, bash, CA bundle) are interpolated
    # into the constants below, so some lines are unavoidably long.
    flakeIgnore = [ "E501" ];
  }
  ''
    """Run one opencode2 shell command inside an OpenSandbox container.

    opencode2 invokes the configured shell as `<shell> -c <command>` with the
    session directory as the working directory. Commands are executed in a
    per-workspace sandbox instead of the host shell; output streams through
    unchanged and the remote exit status becomes this process's exit status.

    Diagnostics are silent unless OPENCODE2_SANDBOX_DEBUG=1; a failure prints
    one line on stderr and exits non-zero.
    """

    import fcntl
    import hashlib
    import logging
    import os
    import pwd
    import subprocess
    import sys
    from datetime import timedelta

    from opensandbox.config.connection_sync import ConnectionConfigSync
    from opensandbox.models.execd import RunCommandOpts
    from opensandbox.models.execd_sync import ExecutionHandlersSync
    from opensandbox.models.sandboxes import Host, SandboxImageSpec, Volume
    from opensandbox.sync.sandbox import SandboxSync

    # Substituted at build time by home/opencode-sandbox-shell.nix.
    IMAGE = "${work.sandboxTypes.shell.image}"
    GIT = "${lib.getExe pkgs.git}"
    HOST_BASH = "${pkgs.bashInteractive}/bin/bash"
    CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    # home/opensandbox.nix's serverPort; the key file is the same per-boot file
    # the osb wrappers read, so OPEN_SANDBOX_DOMAIN/OPEN_SANDBOX_API_KEY can
    # point the shell at a remote server instead.
    DEFAULT_DOMAIN = "127.0.0.1:8090"

    SANDBOX_TIMEOUT = timedelta(hours=12)
    READY_TIMEOUT = timedelta(minutes=15)
    REQUEST_TIMEOUT = timedelta(seconds=900)
    # Matches dsh's workspace world: a cold image pull is the slow case, so the
    # ready timeout covers it, and the server clamps runaway requests at its own
    # maxima (8 CPUs / 16 GiB).
    RESOURCES = {"cpu": "4", "memory": "8Gi"}

    STATE_ROOT = os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
        "opensandbox",
        "opencode-shell",
    )

    DEBUG = os.environ.get("OPENCODE2_SANDBOX_DEBUG") == "1"


    def log(message):
        if DEBUG:
            print(f"opencode-sandbox-shell: {message}", file=sys.stderr)


    def api_key():
        direct = os.environ.get("OPEN_SANDBOX_API_KEY", "")
        if direct:
            return direct
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        try:
            with open(os.path.join(runtime, "opensandbox", "api-key"), encoding="utf-8") as handle:
                return handle.read().strip()
        except OSError:
            return ""


    def connection_config():
        return ConnectionConfigSync(
            api_key=api_key(),
            domain=os.environ.get("OPEN_SANDBOX_DOMAIN", DEFAULT_DOMAIN),
            request_timeout=REQUEST_TIMEOUT,
            disable_metrics=True,
        )


    def workspace_root(cwd):
        """The git toplevel above cwd, else cwd itself.

        Mounting the repository root rather than a subdirectory keeps `git`
        commands working when the shell tool's cwd is nested, while still
        bounding the sandbox to the project the session is working on.
        """
        root = os.path.realpath(cwd)
        try:
            probe = subprocess.run(
                [GIT, "-C", root, "rev-parse", "--show-toplevel"],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return root
        top = probe.stdout.strip()
        if probe.returncode == 0 and top:
            top = os.path.realpath(top)
            if os.path.isdir(top):
                return top
        return root


    def sanitize_metadata(value):
        slug = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in value)
        slug = slug.lstrip(".-").rstrip(".-")[:63]
        return slug or "workspace"


    def container_env():
        """Environment for every command in the sandbox.

        PATH keeps only host entries whose real path lives under the read-only
        /nix/store mount, because any other host directory would be a dangling
        PATH entry inside the container; the image's own system directories
        follow. The CA variables name the NixOS bundle through that same mount:
        the Debian image has no system trust store.
        """
        entries = []
        seen = set()

        def add(path):
            try:
                real = os.path.realpath(path)
            except OSError:
                return
            if not real.startswith("/nix/store/") or not os.path.isdir(real):
                return
            if real not in seen:
                seen.add(real)
                entries.append(real)

        for entry in os.environ.get("PATH", "").split(":"):
            if entry:
                add(entry)
        home = os.path.expanduser("~")
        user = os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name
        for entry in (
            "/run/current-system/sw/bin",
            os.path.join(home, ".nix-profile", "bin"),
            os.path.join("/etc/profiles/per-user", user, "bin"),
        ):
            add(entry)
        entries.extend(["/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin"])
        return {
            "PATH": ":".join(entries),
            "HOME": "/root",
            "TERM": "dumb",
            "LANG": "C.UTF-8",
            "SSL_CERT_FILE": CA_BUNDLE,
            "NIX_SSL_CERT_FILE": CA_BUNDLE,
            "GIT_SSL_CAINFO": CA_BUNDLE,
            "CURL_CA_BUNDLE": CA_BUNDLE,
        }


    def volumes_for(root):
        return [
            Volume(name="workspace", host=Host(path=root), mount_path=root),
            Volume(
                name="nix-store",
                host=Host(path="/nix/store"),
                mount_path="/nix/store",
                read_only=True,
            ),
        ]


    def create_sandbox(root, config):
        log(f"creating a sandbox for {root}")
        return SandboxSync.create(
            SandboxImageSpec(image=IMAGE),
            timeout=SANDBOX_TIMEOUT,
            ready_timeout=READY_TIMEOUT,
            env=container_env(),
            resource=RESOURCES,
            # The workload entrypoint only has to keep the container alive;
            # execd, injected by the server, runs the commands.
            entrypoint=["/bin/sh", "-c", "exec sleep infinity"],
            metadata={
                "name": "opencode2-shell",
                "codebam.opencode.workspace": sanitize_metadata(root),
            },
            volumes=volumes_for(root),
            connection_config=config,
        )


    def reuse_sandbox(sandbox_id, config):
        """Reconnect to a recorded sandbox, or None when it is gone/replaced."""
        try:
            sandbox = SandboxSync.connect(sandbox_id, connection_config=config, skip_health_check=True)
        except Exception:
            return None
        try:
            state = str(sandbox.get_info().status.state)
        except Exception:
            sandbox.close()
            return None
        if state.lower() == "running":
            log(f"reusing sandbox {sandbox_id}")
            return sandbox
        sandbox.close()
        return None


    def ensure_sandbox(root, config):
        """The sandbox for one workspace root, creating one under a file lock.

        Parallel shell calls for the same workspace share the lock, so only one
        of them creates the container; callers that arrive later reuse the
        recorded id. The id survives reboots with the rest of ~/.local/state/
        opensandbox, and a stale id (TTL reaped, host rebooted) is replaced
        here.
        """
        os.makedirs(STATE_ROOT, mode=0o700, exist_ok=True)
        key = hashlib.sha256(root.encode("utf-8")).hexdigest()[:16]
        id_file = os.path.join(STATE_ROOT, key + ".id")
        lock_file = os.path.join(STATE_ROOT, key + ".lock")
        with open(lock_file, "w", encoding="utf-8") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if os.path.exists(id_file):
                with open(id_file, encoding="utf-8") as handle:
                    sandbox_id = handle.read().strip()
                if sandbox_id:
                    sandbox = reuse_sandbox(sandbox_id, config)
                    if sandbox is not None:
                        return sandbox
                    log(f"sandbox {sandbox_id} is gone; replacing it")
            sandbox = create_sandbox(root, config)
            with open(id_file, "w", encoding="utf-8") as handle:
                handle.write(sandbox.id + "\n")
            return sandbox


    def run_command(sandbox, command, cwd):
        """Stream one remote command and return its exit status.

        execd reports stdout/stderr as one event per line with the separator
        stripped, so each event is re-emitted with its newline; that keeps the
        line structure the agent expects. A non-zero remote status arrives as
        an error event whose value is the exit code.
        """

        def handler(stream):
            def emit(message):
                stream.write((message.text or "") + "\n")
                stream.flush()

            return emit

        execution = sandbox.commands.run(
            command,
            opts=RunCommandOpts(working_directory=cwd),
            handlers=ExecutionHandlersSync(
                on_stdout=handler(sys.stdout),
                on_stderr=handler(sys.stderr),
                skip_accumulation=True,
            ),
        )
        if execution.error:
            raw = str(execution.error.value or "")
            log(f"remote command failed: {execution.error.name}: {raw}")
            try:
                return int(raw)
            except ValueError:
                return 1
        return 0


    def main(argv):
        if os.environ.get("OPENCODE2_NO_SANDBOX"):
            os.execv(HOST_BASH, [HOST_BASH] + argv)
        if not (len(argv) >= 2 and argv[0] in ("-c", "-lc")):
            # Interactive or an argument shape this wrapper does not run in the
            # sandbox (the TUI terminal opens the shell with no -c): host shell.
            os.execv(HOST_BASH, [HOST_BASH] + argv)

        # SDK warnings about a reaped sandbox are expected during replacement
        # and would otherwise interleave with command output.
        logging.getLogger("opensandbox").setLevel(logging.CRITICAL)

        # realpath as well as the mount root: a symlinked session directory
        # must name the path the bind mount actually exposes in the container.
        cwd = os.path.realpath(os.getcwd())
        root = workspace_root(cwd)
        config = connection_config()
        sandbox = ensure_sandbox(root, config)
        try:
            return run_command(sandbox, argv[1], cwd)
        finally:
            sandbox.close()


    if __name__ == "__main__":
        try:
            sys.exit(main(sys.argv[1:]))
        except Exception as error:
            print(f"opencode-sandbox-shell: {error}", file=sys.stderr)
            sys.exit(1)
  ''
