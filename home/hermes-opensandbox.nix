# The Hermes terminal backend plugin that runs commands through OpenSandbox.
#
# Mirrors the wrappers beside it in intent (home/opencode-sandbox-shell.nix,
# dsh's OpenSandbox world): the agent's terminal and file tools execute in a
# container bound to the session workspace -- workspace bind-mounted read-write
# at its host path, /nix/store read-only, no host Nix daemon, no credentials,
# an ephemeral /root. Where opencode2 replaces its `shell` executable, Hermes
# takes a registered terminal backend: this is a Hermes plugin (kind: backend)
# whose provider spawns home/opensandbox-exec.nix's executor once per command,
# and `terminal.backend = "opensandbox"` in home/hermes.nix selects it.
#
# Two guards run before a container is asked for, mirroring the server's own
# rules so an impossible workspace lands as a clear fallback instead of a
# create-time error: the workspace root must sit under allowedHostPaths and
# must not contain a protected path (both from home/opensandbox-paths.nix). A
# workspace that fails them -- a bare home directory is the typical case, it
# contains ~/.gnupg -- runs on the host shell with a one-time notice in the
# first command's output; HERMES_OPENSANDBOX_FALLBACK=error refuses instead,
# and HERMES_NO_SANDBOX=1 bypasses the sandbox for the whole process.
{
  config,
  pkgs,
  lib,
}:

let
  exec = import ./opensandbox-exec.nix { inherit pkgs lib; };
  paths = import ./opensandbox-paths.nix { home = config.home.homeDirectory; };

  # The module body; the build-time constants (executor path, the two guard
  # lists) are interpolated so the plugin never re-derives a policy value.
  initPy = pkgs.writeTextFile {
    name = "hermes-opensandbox-plugin.py";
    text = ''
      """Hermes terminal backend: run commands in OpenSandbox containers.

      The provider registers the "opensandbox" terminal backend (selected with
      `terminal.backend: opensandbox` in config.yaml, and listed in
      `plugins.enabled`). Every command a session runs -- the terminal tool and
      the file tools that dispatch through the backend -- executes inside a
      container bound to the session workspace: the workspace is bind-mounted
      read-write at its host path, /nix/store read-only, and the container gets
      no host Nix daemon, no credentials, and an ephemeral /root. That is the
      same untrusted-agent tier as opencode2's shell and dsh's default world.

      Workspace resolution: the session's directory (per-task override, then
      the session cwd record, then the cwd passed with the environment request)
      is resolved to its git toplevel. A directory that cannot be a sandbox
      workspace -- missing, outside the server's allowed host paths, or
      containing a protected credential path (home/opensandbox-paths.nix) --
      falls back to the host shell with a one-time notice appended to the first
      command's output. HERMES_OPENSANDBOX_FALLBACK=error refuses instead, and
      HERMES_NO_SANDBOX=1 bypasses the sandbox for the whole process: the
      analogues of opencode2's OPENCODE2_NO_SANDBOX and dsh's
      DSH_NO_OPENSANDBOX escape hatches.
      """

      import hashlib
      import logging
      import os
      import socket
      import subprocess
      import tempfile
      from pathlib import Path

      from agent.terminal_env_provider import TerminalEnvironmentProvider
      from tools.environments.base import BaseEnvironment
      from tools.environments.local import LocalEnvironment

      logger = logging.getLogger("hermes.plugins.opensandbox")

      # Substituted at build time by home/hermes-opensandbox.nix.
      EXEC_BIN = "${exec}/bin/opensandbox-exec"
      PROTECTED_PATHS = ${builtins.toJSON paths.readonlyHostPaths}
      ALLOWED_HOST_PATHS = ${builtins.toJSON paths.allowedHostPaths}

      # Mirrors the defaults in home/opensandbox-exec.nix; the server clamps
      # runaway requests at its own maxima (8 CPUs / 16 GiB).
      DEFAULT_CPU = "4"
      DEFAULT_MEMORY = "8Gi"
      # home/opensandbox.nix's serverPort, for the doctor reachability probe.
      SERVER_DOMAIN = "127.0.0.1:8090"


      def _truthy(value):
          return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


      def _host_path(value):
          """An absolute real host path from a config value, or "" when unusable."""
          text = str(value or "").strip()
          if not text:
              return ""
          text = os.path.expanduser(text)
          if not os.path.isabs(text):
              text = os.path.join(os.getcwd(), text)
          return os.path.realpath(text)


      def _session_cwd(cwd, task_id):
          """The best host anchor for the session's workspace.

          Preference order matches the terminal tool's own resolution: the
          per-task cwd override, then the session's recorded cwd, then the cwd
          this request carried, then the process directory. Reading the two
          records through their core helpers is deliberate and fail-soft: if
          that API moves, the request cwd is still a correct answer.
          """
          candidates = []
          try:
              from tools.terminal_tool import get_session_cwd, resolve_task_overrides

              try:
                  overrides = resolve_task_overrides(task_id) or {}
              except Exception:
                  overrides = {}
              if isinstance(overrides, dict):
                  candidates.append(overrides.get("cwd"))
              candidates.append(get_session_cwd(task_id))
          except Exception:
              pass
          candidates.append(cwd)
          for candidate in candidates:
              if isinstance(candidate, str) and candidate.strip():
                  return _host_path(candidate)
          return os.path.realpath(os.getcwd())


      def _workspace_root(path):
          """The git toplevel above path, else path itself.

          The executor mounts this root rather than the session directory so
          `git` keeps working when a command runs in a subdirectory, while the
          sandbox still stays bounded to the project. Same rule as
          home/opensandbox-exec.nix's callers and opencode2's shell.
          """
          try:
              probe = subprocess.run(
                  ["git", "-C", path, "rev-parse", "--show-toplevel"],
                  capture_output=True,
                  text=True,
                  timeout=10,
                  check=False,
              )
          except (OSError, subprocess.SubprocessError):
              return path
          top = probe.stdout.strip() if probe.stdout else ""
          if probe.returncode == 0 and top:
              top = os.path.realpath(top)
              if os.path.isdir(top):
                  return top
          return path


      def _unmountable_reason(root):
          """The first server-side guard that keeps root from being a workspace.

          Mirrors the server's [storage] rules (a bind whose source is, or
          contains, a protected credential/control path is refused or forced
          read-only) plus its allowed_host_paths prefixes. The server re-checks
          all three; this only makes the fallback decision before a container
          is asked for.
          """
          if not os.path.isdir(root):
              return f"{root} is not an existing directory"
          for protected in PROTECTED_PATHS:
              if root == protected:
                  return f"{root} is a protected host path (the server mounts it read-only)"
              if protected.startswith(root.rstrip("/") + "/"):
                  return f"{root} contains the protected host path {protected}"
          in_allowed = any(
              root == allowed.rstrip("/") or root.startswith(allowed.rstrip("/") + "/")
              for allowed in ALLOWED_HOST_PATHS
          )
          if not in_allowed:
              return f"{root} is outside the server's allowed host paths"
          return None


      def _api_key_present():
          if os.environ.get("OPEN_SANDBOX_API_KEY", "").strip():
              return True
          runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
          try:
              return bool(Path(runtime, "opensandbox", "api-key").read_text(encoding="utf-8").strip())
          except OSError:
              return False


      def _server_reachable(timeout=0.3):
          host, _, port = SERVER_DOMAIN.partition(":")
          try:
              with socket.create_connection((host or "127.0.0.1", int(port or 8090)), timeout=timeout):
                  return True
          except OSError:
              return False


      def _container_persistent():
          """terminal.container_persistent, read scope-aware like the built-ins."""
          try:
              from tools.terminal_tool_config import _tenv_bool

              return _tenv_bool("TERMINAL_CONTAINER_PERSISTENT", "true")
          except Exception:
              return True


      class HostFallbackEnvironment(LocalEnvironment):
          """The local backend, plus one model-visible notice that it is not sandboxed."""

          def __init__(self, *, reason, bypass=False, **kwargs):
              super().__init__(**kwargs)
              if bypass:
                  self._opensandbox_notice = (
                      "[opensandbox] HERMES_NO_SANDBOX=1 is set: this session's commands "
                      "run on the host shell, not in an OpenSandbox container."
                  )
              else:
                  self._opensandbox_notice = (
                      f"[opensandbox] this session's workspace cannot be sandboxed ({reason}); "
                      "commands run on the host shell instead. Start a session inside a "
                      "project directory for sandboxed execution."
                  )

          def execute(self, command, *args, **kwargs):
              result = super().execute(command, *args, **kwargs)
              notice, self._opensandbox_notice = self._opensandbox_notice, ""
              if notice and isinstance(result, dict):
                  output = result.get("output")
                  if isinstance(output, str) and output:
                      result["output"] = output + "\n" + notice
                  else:
                      result["output"] = notice
              return result


      class OpensandboxEnvironment(BaseEnvironment):
          """Commands run in an OpenSandbox container bound to the workspace root.

          Each _run_bash spawns home/opensandbox-exec.nix's executor with the
          wrapped script as its argv; the executor reuses the workspace
          container and streams output back, so the parent-side machinery
          (login-shell snapshot, cwd tracking, timeouts, output caps) stays the
          base class's, unchanged. A command's stdin goes to the executor as a
          host file (see _stdin_mode), which stages it inside the sandbox.
          """

          # stdin is staged as a file, not embedded as a heredoc: the executor
          # uploads the payload through the sandbox files API and runs the
          # command with `< file`, so the bytes arrive verbatim. The file tools
          # verify a sha256 of what they wrote, and heredoc framing both appends
          # a trailing newline and binds the redirect to the script's last
          # command rather than the reader. This is the base class's default
          # "pipe" contract, delivered by the executor.
          _stdin_mode = "pipe"
          # The first executor call can pay for a cold image pull (it allows 15
          # minutes to become ready), so the snapshot bootstrap needs more room
          # than the 30s default.
          _snapshot_timeout = 900

          def __init__(self, *, cwd, root, timeout, task_id="default", persistent=True, cpu=None, memory=None):
              super().__init__(cwd=cwd, timeout=timeout)
              self._root = root
              self._task_id = str(task_id or "default")
              self._persistent = bool(persistent)
              self._cpu = str(cpu or DEFAULT_CPU)
              self._memory = str(memory or DEFAULT_MEMORY)
              # One key per workspace, or per session in non-persistent mode:
              # the shell backend reuses the executor's recorded container.
              key_source = root if self._persistent else root + "\x00" + self._task_id
              self._key = hashlib.sha256(key_source.encode("utf-8")).hexdigest()[:16]
              self.init_session()

          def _helper_cwd(self):
              cwd = self.cwd or self._root
              if cwd == self._root or cwd.startswith(self._root.rstrip("/") + "/"):
                  return cwd
              return self._root

          def _run_bash(self, cmd_string, *, login=False, timeout=120, stdin_data=None):
              argv = [
                  EXEC_BIN,
                  "--key",
                  self._key,
                  "--root",
                  self._root,
                  "--cwd",
                  self._helper_cwd(),
                  "--timeout",
                  str(int(timeout) if timeout else 0),
                  "--cpu",
                  self._cpu,
                  "--memory",
                  self._memory,
              ]
              stdin_path = ""
              if stdin_data is not None:
                  # One host temp file per payload; the executor reads it,
                  # stages it in the sandbox and deletes it, so it does not
                  # outlive the command. surrogateescape matches the encoding
                  # the write tool hashes, keeping the round trip byte-exact.
                  fd, stdin_path = tempfile.mkstemp(prefix="hermes-opensandbox-stdin-")
                  with os.fdopen(fd, "wb") as handle:
                      handle.write(stdin_data.encode("utf-8", "surrogateescape"))
                  argv += ["--stdin-file", stdin_path]
              argv += ["--", "/bin/bash", "-lc" if login else "-c", cmd_string]
              try:
                  return subprocess.Popen(
                      argv,
                      stdin=subprocess.DEVNULL,
                      stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT,
                      text=True,
                      encoding="utf-8",
                      errors="replace",
                      cwd=self._root,
                  )
              except BaseException:
                  # A spawn that never reached the executor would otherwise
                  # leave the payload behind in this process's temp dir.
                  if stdin_path:
                      try:
                          os.unlink(stdin_path)
                      except OSError:
                          pass
                  raise

          def cleanup(self):
              if self._persistent:
                  # The workspace container outlives sessions until the
                  # server's TTL reaps it: same contract as opencode2's shell.
                  logger.debug("opensandbox: keeping sandbox %s for %s", self._key, self._root)
                  return
              try:
                  done = subprocess.run(
                      [EXEC_BIN, "--key", self._key, "--destroy"],
                      capture_output=True,
                      text=True,
                      timeout=120,
                      check=False,
                  )
              except Exception as error:
                  logger.warning("opensandbox: destroying %s failed: %s", self._key, error)
                  return
              if done.returncode != 0:
                  logger.warning("opensandbox: destroying %s failed: %s", self._key, (done.stderr or "").strip())


      class OpensandboxProvider(TerminalEnvironmentProvider):
          """The "opensandbox" terminal backend: OpenSandbox workspace containers."""

          name = "opensandbox"
          display_name = "OpenSandbox"
          is_remote = True
          # The container has its own filesystem, but the workspace is mounted
          # at its host path: host-looking cwds are correct as-is, and the
          # container-path sanitizing and file-tool translation that
          # is_container triggers would break both. Dangerous-command approval
          # stays on for the same reason: this backend mounts real host paths.
          is_container = False

          @property
          def description(self):
              return "Run commands in an OpenSandbox container bound to the session workspace."

          @property
          def env_description(self):
              return "an OpenSandbox workspace container (Linux, host workspace bind-mounted)"

          @property
          def strip_env_keys(self):
              # The per-boot sandbox key is a credential for a single-user
              # loopback daemon; a model-authored command has no reason to
              # hold it.
              return frozenset({"OPEN_SANDBOX_API_KEY"})

          def is_available(self):
              return Path(EXEC_BIN).exists() and _api_key_present()

          def check_requirements(self, config):
              if not Path(EXEC_BIN).exists():
                  logger.warning(
                      "opensandbox: executor %s is missing (rebuild and activate the home profile)", EXEC_BIN
                  )
                  return False
              if not _api_key_present():
                  logger.warning(
                      "opensandbox: no API key; start opensandbox-server.service "
                      "(home/opensandbox.nix), which writes the per-boot key file"
                  )
                  return False
              return True

          def probe(self):
              if not Path(EXEC_BIN).exists():
                  return ("needs_setup", f"executor {EXEC_BIN} is not installed")
              if not _api_key_present():
                  return ("needs_setup", "no OpenSandbox API key (is opensandbox-server running?)")
              return ("ready", "")

          def doctor_checks(self):
              reachable = _server_reachable()
              return [
                  (Path(EXEC_BIN).exists(), "OpenSandbox executor", EXEC_BIN),
                  (_api_key_present(), "OpenSandbox API key", "per-boot key file / OPEN_SANDBOX_API_KEY"),
                  (
                      reachable,
                      "OpenSandbox server",
                      SERVER_DOMAIN + (" reachable" if reachable else " not reachable (opensandbox-server.service)"),
                  ),
              ]

          def create_environment(self, *, cwd="", timeout=180, task_id="default", image=None, container_config=None, **kwargs):
              if _truthy(os.environ.get("HERMES_NO_SANDBOX", "")):
                  return self._host_fallback(cwd, timeout, bypass=True)
              requested = _session_cwd(cwd, task_id)
              root = _workspace_root(requested)
              reason = _unmountable_reason(root)
              if reason is not None:
                  if os.environ.get("HERMES_OPENSANDBOX_FALLBACK", "local").strip().lower() == "error":
                      raise ValueError(
                          f"OpenSandbox backend: cannot sandbox {requested} ({reason}). "
                          "Start the session in a project directory, set "
                          "HERMES_OPENSANDBOX_FALLBACK=local to run on the host, or "
                          "HERMES_NO_SANDBOX=1 to bypass deliberately."
                      )
                  logger.warning("opensandbox: %s cannot be sandboxed (%s); running on the host", requested, reason)
                  return self._host_fallback(requested, timeout, reason=reason)
              return OpensandboxEnvironment(
                  cwd=requested,
                  root=root,
                  timeout=timeout,
                  task_id=task_id,
                  persistent=_container_persistent(),
                  cpu=os.environ.get("HERMES_OPENSANDBOX_CPU", DEFAULT_CPU),
                  memory=os.environ.get("HERMES_OPENSANDBOX_MEMORY", DEFAULT_MEMORY),
              )

          def _host_fallback(self, cwd, timeout, reason="", bypass=False):
              anchor = _host_path(cwd) or os.path.realpath(os.getcwd())
              return HostFallbackEnvironment(cwd=anchor, timeout=timeout, reason=reason, bypass=bypass)


      def register(ctx):
          ctx.register_terminal_environment_provider(OpensandboxProvider())
    '';
  };

  pluginYaml = pkgs.writeTextFile {
    name = "hermes-opensandbox-plugin.yaml";
    text = ''
      name: opensandbox
      version: 0.1.0
      description: Run Hermes terminal commands in OpenSandbox containers bound to the session workspace.
      kind: backend
    '';
  };
in
pkgs.runCommand "hermes-opensandbox"
  {
    meta.description = "Hermes terminal backend plugin backed by OpenSandbox";
  }
  ''
    mkdir -p $out
    cp ${initPy} $out/__init__.py
    # Syntax gate: a plugin that cannot compile would otherwise fail silently
    # at load time in every Hermes process.
    ${pkgs.python3}/bin/python3 -m py_compile $out/__init__.py
    rm -rf $out/__pycache__
    cp ${pluginYaml} $out/plugin.yaml
  ''
