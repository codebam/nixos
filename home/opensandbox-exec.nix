# The OpenSandbox-backed command executor for Hermes.
#
# Hermes' terminal backend plugin (home/hermes-opensandbox.nix) spawns this
# executable once per command, handing it the command's argv: the process
# ensures the workspace container exists, runs the command inside it over the
# server's execd API, streams output back on stdout/stderr, and exits with the
# remote status. The container tier matches opencode2's shell
# (home/opencode-sandbox-shell.nix) and dsh's default world: the workspace is
# bind-mounted read-write at its own host path, /nix/store read-only so host
# toolchains resolve, and the container gets no Nix daemon, no credentials,
# and an ephemeral /root.
#
# The sandbox is keyed by the caller (one key per workspace, or per session in
# the non-persistent mode) and reused until the server's TTL reaps it, so a
# session pays the container start once. State lives beside the opencode-shell
# state under ~/.local/state/opensandbox/ (preserved across reboots by
# modules/system/preservation.nix); the key namespaces keep the two harnesses
# from fighting over one container.
#
# `--stdin-file PATH` carries a command's stdin: the payload is uploaded into
# the sandbox through the server's files API (content arrives verbatim) and the
# command runs with `< file`, because execd itself has no stdin channel. The
# heredoc embedding Hermes' base class offers instead cannot serve the file
# tools: the redirect binds to the script's last command rather than the
# reader, and every heredoc appends a trailing newline their sha256 check
# rejects.
#
# `opensandbox-exec --destroy --key K` deletes the sandbox recorded for a key
# (the plugin calls it when a non-persistent session ends). OPEN_SANDBOX_DOMAIN
# / OPEN_SANDBOX_API_KEY in the environment override the loopback default and
# the per-boot key file, the same contract as the osb wrappers.
{
  pkgs,
  lib,
}:

let
  # The pinned image from the per-work-type catalog, so the digest still lives
  # in exactly one place; the `shell` type is the closest fit for command
  # execution (minimal POSIX userland, no language runtime).
  work = import ./opensandbox-work.nix { inherit pkgs lib; };
in
pkgs.writers.writePython3Bin "opensandbox-exec"
  {
    libraries = [ pkgs.opensandbox ];
    # Build-time store paths (image, CA bundle) are interpolated into the
    # constants below, so some lines are unavoidably long.
    flakeIgnore = [ "E501" ];
  }
  ''
    """Run one command inside an OpenSandbox container, for a host harness.

    Usage: opensandbox-exec [options] -- COMMAND [ARG...]

    Options:
      --key KEY        reuse identity for the sandbox (required)
      --root DIR       host directory to bind at its own path, read-write
                       (repeatable; the sandbox is keyed by the caller)
      --cwd DIR        working directory inside the container
      --timeout SECS   server-side limit; on expiry the command is killed and
                       this process exits 124
      --cpu N          CPUs for a newly created sandbox (default 4)
      --memory SIZE    memory for a newly created sandbox (default 8Gi)
      --name NAME      sandbox metadata name (default hermes-shell)
      --stdin-file F   upload F's bytes into the sandbox and run the command
                       with them as its stdin; F is deleted afterwards
      --destroy        delete the sandbox recorded for KEY, then exit
      --debug          diagnostics on stderr (or OPENSANDBOX_EXEC_DEBUG=1)

    Diagnostics are silent otherwise; a failure prints one line on stderr and
    exits non-zero.
    """

    import fcntl
    import logging
    import os
    import pwd
    import shlex
    import sys
    import uuid
    from datetime import timedelta

    from opensandbox.config.connection_sync import ConnectionConfigSync
    from opensandbox.models.execd import RunCommandOpts
    from opensandbox.models.execd_sync import ExecutionHandlersSync
    from opensandbox.models.sandboxes import Host, SandboxImageSpec, Volume
    from opensandbox.sync.sandbox import SandboxSync

    # Substituted at build time by home/opensandbox-exec.nix.
    IMAGE = "${work.sandboxTypes.shell.image}"
    CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

    # home/opensandbox.nix's serverPort; the key file is the same per-boot file
    # the osb wrappers read, so OPEN_SANDBOX_DOMAIN/OPEN_SANDBOX_API_KEY can
    # point the executor at a remote server instead.
    DEFAULT_DOMAIN = "127.0.0.1:8090"

    SANDBOX_TIMEOUT = timedelta(hours=12)
    READY_TIMEOUT = timedelta(minutes=15)
    # A streaming request is one HTTP request for its whole duration, so this
    # bounds how long a single remote command may run before the connection
    # itself is abandoned (opencode-sandbox-shell uses the same constant).
    REQUEST_TIMEOUT = timedelta(seconds=900)
    # The server clamps runaway requests at its own maxima (8 CPUs / 16 GiB);
    # a cold image pull is the slow case that READY_TIMEOUT covers.
    DEFAULT_CPU = "4"
    DEFAULT_MEMORY = "8Gi"
    # Where a command's stdin payload is staged inside the container; the
    # runner deletes it once the command has exited.
    STDIN_STAGE_TEMPLATE = "/tmp/.hermes-stdin-{}"

    STATE_ROOT = os.path.join(
        os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
        "opensandbox",
        "hermes-shell",
    )

    DEBUG = os.environ.get("OPENSANDBOX_EXEC_DEBUG") == "1"


    def log(message):
        if DEBUG:
            print(f"opensandbox-exec: {message}", file=sys.stderr)


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


    def volumes_for(roots):
        """The workspace binds plus the read-only store, at their host paths.

        Mounting each root at its own host path keeps host-path semantics
        inside the container: the session cwd, file tools, and script cd
        targets all name the same paths they do on the host.
        """
        volumes = []
        for index, root in enumerate(roots):
            name = "workspace" if index == 0 else f"workspace-{index + 1}"
            volumes.append(Volume(name=name, host=Host(path=root), mount_path=root))
        volumes.append(
            Volume(name="nix-store", host=Host(path="/nix/store"), mount_path="/nix/store", read_only=True)
        )
        return volumes


    def create_sandbox(roots, opts, config):
        log(f"creating a sandbox for {', '.join(roots) or '(no workspace)'}")
        return SandboxSync.create(
            SandboxImageSpec(image=IMAGE),
            timeout=SANDBOX_TIMEOUT,
            ready_timeout=READY_TIMEOUT,
            env=container_env(),
            resource={"cpu": opts["cpu"], "memory": opts["memory"]},
            # The workload entrypoint only has to keep the container alive;
            # execd, injected by the server, runs the commands.
            entrypoint=["/bin/sh", "-c", "exec sleep infinity"],
            metadata={
                "name": opts["name"],
                "codebam.hermes.workspace": sanitize_metadata(",".join(roots) or "none"),
            },
            volumes=volumes_for(roots),
            connection_config=config,
        )


    PROFILE_SNIPPET = "/etc/profile.d/00-opensandbox-host-tools.sh"


    def configure_profile(sandbox):
        """Keep the container env PATH through login shells.

        Debian's /etc/profile force-sets PATH for root, discarding the PATH the
        sandbox was created with -- and with it every /nix/store toolchain the
        read-only mount exposes, because container_env rewrites host PATH
        entries to their store realpaths. Profile snippets are sourced after
        that reset, so one snippet re-exports the intended PATH for every login
        shell (Hermes' snapshot bootstrap is one). Only new sandboxes are
        touched; one that predates this setup can be replaced with --destroy.
        """
        path = container_env()["PATH"]
        script = f"mkdir -p /etc/profile.d && printf '%s\\n' 'export PATH={path}' > {PROFILE_SNIPPET}"
        try:
            execution = sandbox.commands.run(script)
        except Exception as error:
            print(f"opensandbox-exec: profile setup failed: {error}", file=sys.stderr)
            return
        if execution.error:
            print(
                f"opensandbox-exec: profile setup failed: {execution.error.name}: {execution.error.value}",
                file=sys.stderr,
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


    def ensure_sandbox(roots, opts, config):
        """The sandbox for one key, creating one under a file lock.

        Parallel commands for the same key share the lock, so only one of them
        creates the container; callers that arrive later reuse the recorded id.
        The id survives reboots with the rest of ~/.local/state/opensandbox,
        and a stale id (TTL reaped, host rebooted) is replaced here.
        """
        os.makedirs(STATE_ROOT, mode=0o700, exist_ok=True)
        key = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in opts["key"])[:64] or "default"
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
            sandbox = create_sandbox(roots, opts, config)
            configure_profile(sandbox)
            with open(id_file, "w", encoding="utf-8") as handle:
                handle.write(sandbox.id + "\n")
            return sandbox


    def destroy_recorded(key, config):
        """Delete the sandbox recorded for a key (best effort, idempotent).

        The caller uses this to end a non-persistent session; a missing
        record or an already-reaped sandbox is success, because the desired
        end state is the same.
        """
        key = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in key)[:64] or "default"
        id_file = os.path.join(STATE_ROOT, key + ".id")
        if not os.path.exists(id_file):
            log(f"no sandbox recorded for {key}")
            return 0
        with open(id_file, encoding="utf-8") as handle:
            sandbox_id = handle.read().strip()
        if not sandbox_id:
            os.unlink(id_file)
            return 0
        try:
            sandbox = SandboxSync.connect(sandbox_id, connection_config=config, skip_health_check=True)
        except Exception as error:
            log(f"sandbox {sandbox_id} is already gone ({error})")
            os.unlink(id_file)
            return 0
        try:
            sandbox.destroy()
        except Exception as error:
            print(f"opensandbox-exec: destroy failed: {error}", file=sys.stderr)
            return 1
        finally:
            try:
                sandbox.close()
            except Exception:
                pass
        log(f"destroyed sandbox {sandbox_id}")
        try:
            os.unlink(id_file)
        except OSError:
            pass
        return 0


    def stage_stdin(sandbox, host_path):
        """Upload the stdin payload at host_path into the sandbox: remote path.

        The files API carries the bytes as an octet stream, so what lands in
        the container is exactly what the host file holds; a shell heredoc
        cannot promise that (it appends a newline, and loses the payload
        outright when its reader is not the script's last command).
        """
        remote_path = STDIN_STAGE_TEMPLATE.format(uuid.uuid4().hex[:12])
        with open(host_path, "rb") as handle:
            payload = handle.read()
        sandbox.files.write_file(remote_path, payload)
        log(f"staged {len(payload)} bytes of stdin at {remote_path}")
        return remote_path


    def unstage_stdin(sandbox, remote_path):
        """Best-effort delete of a staged stdin payload (the sandbox outlives it)."""
        try:
            sandbox.files.delete_files([remote_path])
        except Exception as error:
            log(f"could not remove {remote_path}: {error}")


    def run_command(sandbox, argv, cwd, timeout, stdin_path=None):
        """Stream one remote command and return its exit status.

        execd reports stdout/stderr as one event per line with the separator
        stripped, so each event is re-emitted with its newline; that keeps the
        line structure the agent expects. A non-zero remote status arrives as
        an error event whose value is the exit code; a server-side timeout
        surfaces as an error event naming the timeout and exits 124.
        ``stdin_path`` names a payload already staged inside the sandbox
        (stage_stdin): the command reads it as its stdin, and it is removed
        when the run ends.
        """

        def handler(stream):
            def emit(message):
                # execd's per-line events arrive stripped ("abc"), but a blank
                # line arrives with its newline ("\n"): appending one
                # unconditionally doubles every blank line, and anything that
                # reads content off this stream -- the file tools' cat, the
                # patch tool's read-back check -- then sees a file taller than
                # it is.
                text = message.text or ""
                stream.write(text if text.endswith("\n") else text + "\n")
                stream.flush()

            return emit

        command = "exec " + " ".join(shlex.quote(arg) for arg in argv)
        if stdin_path:
            # The redirect rides the exec'd shell, so the command -- and
            # whatever it runs -- reads the staged payload as its stdin: the
            # same contract as a host pipe.
            command += f" < {shlex.quote(stdin_path)}"
        opts = RunCommandOpts(
            working_directory=cwd or None,
            timeout=timedelta(seconds=timeout) if timeout else None,
        )
        try:
            execution = sandbox.commands.run(
                command,
                opts=opts,
                handlers=ExecutionHandlersSync(
                    on_stdout=handler(sys.stdout),
                    on_stderr=handler(sys.stderr),
                    skip_accumulation=True,
                ),
            )
        finally:
            if stdin_path:
                unstage_stdin(sandbox, stdin_path)
        if execution.error:
            name = str(execution.error.name or "")
            raw = str(execution.error.value or "")
            log(f"remote command failed: {name}: {raw}")
            try:
                code = int(raw)
            except ValueError:
                code = 1
            # execd reports a signal/kill as a negative value (the server-side
            # timeout kills the process); name the likely causes rather than
            # returning the raw sentinel, and use the conventional 124.
            if code < 0 or "timeout" in name.lower() or "timeout" in raw.lower():
                limit = f" after {timeout}s" if timeout else ""
                print(
                    f"opensandbox-exec: command did not exit normally (killed{limit}: "
                    "timeout, interrupt, or OOM)",
                    file=sys.stderr,
                )
                return 124
            return code
        return 0


    def parse_args(argv):
        opts = {
            "key": "",
            "roots": [],
            "cwd": "",
            "timeout": None,
            "cpu": DEFAULT_CPU,
            "memory": DEFAULT_MEMORY,
            "name": "hermes-shell",
            "stdin_file": "",
            "destroy": False,
            "debug": DEBUG,
            "command": [],
        }
        value_options = {
            "--root": "roots",
            "--key": "key",
            "--cwd": "cwd",
            "--timeout": "timeout",
            "--cpu": "cpu",
            "--memory": "memory",
            "--name": "name",
            "--stdin-file": "stdin_file",
        }
        index = 0
        while index < len(argv):
            arg = argv[index]
            if arg == "--":
                opts["command"] = argv[index + 1:]
                break
            if arg in value_options:
                index += 1
                if index >= len(argv):
                    raise SystemExit(f"opensandbox-exec: {arg} needs a value")
                value = argv[index]
                if arg == "--root":
                    opts["roots"].append(value)
                elif arg == "--timeout":
                    try:
                        opts["timeout"] = int(value)
                    except ValueError:
                        raise SystemExit(f"opensandbox-exec: --timeout takes seconds, not {value!r}")
                else:
                    opts[value_options[arg]] = value
            elif arg == "--destroy":
                opts["destroy"] = True
            elif arg == "--debug":
                opts["debug"] = True
            else:
                raise SystemExit(f"opensandbox-exec: unknown option {arg}")
            index += 1
        if not opts["key"]:
            raise SystemExit("opensandbox-exec: --key is required")
        if opts["timeout"] == 0:
            opts["timeout"] = None
        return opts


    def main(argv):
        opts = parse_args(argv)
        if opts["debug"]:
            global DEBUG
            DEBUG = True

        # SDK warnings about a reaped sandbox are expected during replacement
        # and would otherwise interleave with command output.
        logging.getLogger("opensandbox").setLevel(logging.CRITICAL)

        config = connection_config()
        if opts["destroy"]:
            return destroy_recorded(opts["key"], config)
        if not opts["command"]:
            raise SystemExit("opensandbox-exec: no command given; see --help contract in home/opensandbox-exec.nix")

        # realpath as well as the mount root: a symlinked workspace directory
        # must name the path the bind mount actually exposes in the container.
        roots = list(dict.fromkeys(os.path.realpath(root) for root in opts["roots"]))
        sandbox = ensure_sandbox(roots, opts, config)
        staged = None
        try:
            if opts["stdin_file"]:
                staged = stage_stdin(sandbox, opts["stdin_file"])
            return run_command(sandbox, opts["command"], opts["cwd"], opts["timeout"], stdin_path=staged)
        finally:
            if opts["stdin_file"]:
                # The payload lives only for this run: the host copy goes away
                # whether staging, the command, or the unstage failed.
                try:
                    os.unlink(opts["stdin_file"])
                except OSError:
                    pass
            sandbox.close()


    if __name__ == "__main__":
        try:
            sys.exit(main(sys.argv[1:]))
        except Exception as error:
            print(f"opensandbox-exec: {error}", file=sys.stderr)
            sys.exit(1)
  ''
