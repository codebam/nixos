/**
 * dsh-nono: a nono-backed `ctx.sandbox` provider plus the human `/nono`
 * command, so a dsh session can switch which nono profile confines the
 * commands it runs.
 *
 * Why this seam: every confined dsh command — the persistent PTY bash backend
 * (`dsh-terminal-bash`) and the one-shot bash executor (`dsh-bash-sandbox`) —
 * spawns through `ctx.sandbox.confine()`. Replacing the platform provider
 * (`dsh-sandbox-local`) with this one makes both spawn
 * `nono run --profile <active> -- <argv>`. Landlock is restrictive-only and
 * stacks, so the effective policy is the dsh process's own sandbox (the
 * launcher's `nono run --profile dsh`) INTERSECTED with the selected profile:
 * this plugin can only add restrictions, never widen the harness.
 *
 * The active profile is per-session state: the `/nono <profile>` command
 * appends a `nono/profile` session event, the unit below folds it through
 * `ctx.sessionProjections`, and the provider reads the fold for the calling
 * session id. The command first closes the caller's persistent shells so the
 * next spawn is re-confined (a shell keeps the profile it was created under).
 * `/nono off` switches the dsh permission preset to danger-full-access, which
 * bypasses `ctx.sandbox` entirely; the stored profile is kept.
 *
 * dsh's read-only sandbox mode is mapped to a write-free profile
 * (`readOnlyProfile`, default `dsh-readonly`): nono cannot revoke one
 * profile's write grants at invocation time, so the selected language profile
 * must not confine a read-only call. Plan mode therefore still cannot write
 * through the shell.
 *
 * Host requirements (see the dsh nono profile in home/agents.nix):
 *   - `~/.config/nono` readable, so the nested nono can resolve user profiles
 *     by name and this plugin can list them;
 *   - `~/.local/state/nono` writable for nono's audit/session state (the
 *     language profiles deny it to the confined child, so project code cannot
 *     tamper with it);
 *   - a private XDG_RUNTIME_DIR under $DSH_HOME, because the outer sandbox
 *     deliberately does not grant `$XDG_RUNTIME_DIR` to dsh. The child inherits
 *     the private value, which its profile denies anyway; only nono's PTY
 *     proxy symlink needs it.
 *
 * `--sandbox-policy landlock` is required: nested nono under the outer nono
 * segfaults when its seccomp TCP baseline runs inside an already-seccomp'd /
 * scope-restricted sandbox (Landlock alone works, and fails closed on kernels
 * that cannot do network filtering with Landlock).
 */

import { execFileSync } from 'node:child_process'
import { accessSync, constants, mkdirSync, readFileSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { z as zod } from 'zod'
import s from '@deepseek-ai/schemastery'
import { dshHomePath } from '@deepseek-ai/dsh-home-paths'
import { SandboxProvider, SandboxUnavailableError } from '@deepseek-ai/dsh-sandbox'

/** Session-projection key and session-event type owning the chosen profile. */
const PROFILE_KEY = 'nonoProfile'
const PROFILE_EVENT = 'nono/profile'

/** One profile name segment: no whitespace, no shell metacharacters. */
const PROFILE_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/u

/** `/nono` words that disable the extra layer instead of selecting a profile. */
const OFF_WORDS = new Set(['off', 'none'])

/** Nono startup failures that mean the sandbox never ran at all. */
const RUNNER_FAILURE_SIGNATURES = [
  'nono: profile not found',
  'nono: sandbox initialization failed',
  'nono: refusing to grant',
]

/** Resolve the user config root the same way nono does. */
function xdgConfigHome() {
  const configured = process.env.XDG_CONFIG_HOME
  return configured !== undefined && configured.trim().length > 0 ? configured : join(homedir(), '.config')
}

/** Where nono keeps user profiles. */
function profileDir() {
  return join(xdgConfigHome(), 'nono', 'profiles')
}

/** Resolve one executable name or absolute path, failing before any spawn. */
function resolveExecutable(configured) {
  const file = String(configured).trim()
  if (file.length === 0) throw new Error('empty executable path')
  if (file.includes('/')) {
    accessSync(file, constants.X_OK)
    return file
  }
  for (const dir of (process.env.PATH ?? '').split(':')) {
    if (dir.length === 0) continue
    const candidate = join(dir, file)
    try {
      accessSync(candidate, constants.X_OK)
      return candidate
    } catch {
      // keep searching
    }
  }
  throw new Error(`executable ${JSON.stringify(file)} not found on PATH`)
}

/** Parse `nono profile list` output into name/description records. */
function parseProfileList(text) {
  const profiles = []
  for (const line of String(text).split(/\r?\n/u)) {
    const match = /^\s{4}(\S+)\s+(.*)$/u.exec(line)
    if (match === null) continue
    const name = match[1]
    if (!PROFILE_NAME_RE.test(name)) continue
    if (profiles.some((entry) => entry.name === name)) continue
    const description = match[2].trim().replace(/\s+extends\s+\S+\s*$/u, '').trim()
    profiles.push({ name, description })
  }
  return profiles
}

/**
 * Registers as `ctx.sandbox` and as the global `/nono` command. Replaces
 * `@deepseek-ai/dsh-sandbox-local` in the profile patch; the confined bash
 * consumers then run commands through the selected nono profile.
 */
export class NonoSandboxProvider extends SandboxProvider {
  static Config = s.object({
    /** Nono executable: an absolute path (recommended) or a PATH lookup. */
    nonoPath: s.string().default('nono'),
    /** `env(1)` used to point nono's own PTY proxy at a private runtime dir. */
    envPath: s.string().default('env'),
    /** Profile for sessions that never ran `/nono <profile>`. */
    defaultProfile: s.string().default('dev-base'),
    /** Nono network/filesystem enforcement policy for nested runs. */
    sandboxPolicy: s.string().default('landlock'),
    /** Private runtime dir, absolute or relative to $DSH_HOME. */
    runtimeDir: s.string().default('nono/run'),
    /**
     * Profile used while dsh is in read-only mode. Nono has no per-invocation
     * read-only override, so the session's language profile (which grants
     * project/cache writes) must not be used for a read-only call. Must grant
     * no project or cache writes.
     */
    readOnlyProfile: s.string().default('dsh-readonly'),
  })

  constructor(ctx, config = {}) {
    super(ctx)
    const raw = config ?? {}
    this.options = {
      nonoPath: textOr(raw.nonoPath, 'nono'),
      envPath: textOr(raw.envPath, 'env'),
      defaultProfile: textOr(raw.defaultProfile, 'dev-base'),
      sandboxPolicy: textOr(raw.sandboxPolicy, 'landlock'),
      runtimeDir: textOr(raw.runtimeDir, 'nono/run'),
      readOnlyProfile: textOr(raw.readOnlyProfile, 'dsh-readonly'),
    }
    this.options.runtimeDir = this.options.runtimeDir.includes('/')
      ? this.options.runtimeDir
      : dshHomePath(this.options.runtimeDir)
    this.executables = new Map()

    // The PTY proxy writes a symlink into XDG_RUNTIME_DIR before the inner
    // sandbox applies; the outer dsh profile grants only $DSH_HOME, so use a
    // private runtime dir instead of the session's (denied to dsh anyway).
    mkdirSync(this.options.runtimeDir, { recursive: true, mode: 0o700 })

    ctx.inject(['commands'], (scope) => {
      scope.commands.register({
        name: 'nono',
        description: 'Select the nono profile that confines this session, or turn the extra layer off',
        input: { hint: '<profile>|off|list' },
        handler: (invocation) => this.handleCommand(invocation),
      })
    })

    ctx.inject(['sessionProjections'], (scope) => {
      scope.sessionProjections.register({
        key: PROFILE_KEY,
        stateVersion: 1,
        stateSchema: zod.string().nullable(),
        init: () => null,
        apply: (state, event) =>
          event?.type === PROFILE_EVENT && typeof event.data?.profile === 'string' && event.data.profile.length > 0
            ? event.data.profile
            : state,
      })
    })

    ctx.inject(['systemPrompt'], (scope) => {
      scope.systemPrompt.context({
        name: 'nono:profile',
        order: scope.systemPrompt.getContextOrder('SANDBOX_POLICY') + 1,
        text: (assembly) => this.renderContext(assembly),
      })
    })
  }

  /**
   * Wrap one caller argv so it runs under the session's active nono profile.
   * Fails closed through {@link SandboxUnavailableError} when nono cannot be
   * resolved; the consumer reports SANDBOX_UNAVAILABLE instead of running bare.
   */
  confine(argv, policy) {
    const profile = this.sandboxProfileFor(policy)
    const mode = policy?.mode ?? 'workspace-write'
    let nono
    let env
    try {
      nono = this.executable('nonoPath')
      env = this.executable('envPath')
    } catch (error) {
      throw new SandboxUnavailableError(mode === 'read-only' ? 'read-only' : 'workspace-write', `nono sandbox: ${messageOf(error)}`)
    }
    const wrapped = [
      env,
      `XDG_RUNTIME_DIR=${this.options.runtimeDir}`,
      nono,
      'run',
      '--silent',
      '--sandbox-policy',
      this.options.sandboxPolicy,
      '--profile',
      profile,
    ]
    if (typeof policy?.workspaceRoot === 'string' && policy.workspaceRoot.length > 0) {
      wrapped.push('--workdir', policy.workspaceRoot)
    }
    wrapped.push('--allow-cwd', '--', ...argv)
    return {
      argv: wrapped,
      enforcement: 'full',
      denialSignatures: ['permission denied', 'operation not permitted'],
      runnerFailureRules: [{ fatalSignatures: RUNNER_FAILURE_SIGNATURES }],
    }
  }

  /**
   * The profile that must confine one call: the session's selected profile,
   * except under dsh's read-only mode, where a profile granting no writes is
   * substituted because nono cannot express a per-invocation write ban.
   */
  sandboxProfileFor(policy) {
    return policy?.mode === 'read-only' ? this.options.readOnlyProfile : this.profileFor(policy)
  }

  /** The profile stored for this call's session, else the configured default. */
  profileFor(policy) {
    const sessionId = policy?.sessionId
    if (sessionId !== undefined) {
      const sessions = this.ctx.get('sessions')
      const session = sessions?.get?.(sessionId)
      if (session !== undefined) {
        const stored = this.storedProfile(session)
        if (stored !== undefined) return stored
      }
    }
    return this.options.defaultProfile
  }

  /** Read the `nonoProfile` projection for one session. */
  storedProfile(session) {
    const registry = this.ctx.get('sessionProjections')
    if (registry === undefined) return undefined
    try {
      const value = registry.stateOf(session, PROFILE_KEY)
      return typeof value === 'string' && value.length > 0 ? value : undefined
    } catch {
      return undefined
    }
  }

  /** Resolve and cache one configured executable. */
  executable(key) {
    const cached = this.executables.get(key)
    if (cached !== undefined) return cached
    const resolved = resolveExecutable(this.options[key])
    this.executables.set(key, resolved)
    return resolved
  }

  /** `/nono [<profile>|off|list]` — the human-facing switch. */
  async handleCommand(invocation) {
    const agent = invocation?.agent
    const session = agent?.session
    if (session === undefined) return { kind: 'error', text: 'nono: this command requires an agent session' }
    const input = String(invocation.rawInput ?? '').trim()
    const profiles = this.listProfiles()
    const current = this.storedProfile(session) ?? this.options.defaultProfile
    if (input.length === 0 || input === 'list') return { kind: 'success', text: this.statusText(session, current, profiles) }
    if (OFF_WORDS.has(input)) return this.disableNono(agent)
    if (!PROFILE_NAME_RE.test(input)) {
      return { kind: 'error', text: `nono: invalid profile name ${JSON.stringify(input)}; use letters, digits, '.', '_' or '-'` }
    }
    if (profiles.length > 0 && !profiles.some((entry) => entry.name === input)) {
      return { kind: 'error', text: `nono: unknown profile ${JSON.stringify(input)}; available: ${profiles.map((entry) => entry.name).join(', ')}` }
    }

    const shells = await this.restartShells(agent)
    const modeNote = this.effectiveMode(session) === 'danger-full-access' ? await this.enableConfinedMode(agent) : ''
    session.append(PROFILE_EVENT, { profile: input })

    const lines = [`nono profile: ${input}`]
    if (shells.count > 0) lines.push(`restarted ${shells.count} persistent shell session(s); the next command starts confined by it`)
    else if (shells.known) lines.push('no open persistent shell; the next command starts confined by it')
    else lines.push('an already-open shell keeps its current profile; run `exit` in it to restart under the new one')
    if (modeNote.length > 0) lines.push(modeNote)
    return { kind: 'success', text: lines.join('\n') }
  }

  /** `/nono off`: stop applying the extra layer without forgetting the profile. */
  async disableNono(agent) {
    const session = agent.session
    const shells = await this.restartShells(agent)
    const presets = this.ctx.get('permissionPresets')
    const approval = this.ctx.get('approval')
    let switched = false
    if (presets !== undefined && Array.isArray(presets.names) && presets.names.includes('danger-full-access')) {
      try {
        presets.apply(session, 'danger-full-access', (policy) => approval?.setPolicy(agent, policy))
        switched = true
      } catch {
        switched = false
      }
    }
    if (!switched) {
      try {
        session.append('sandbox/mode', { mode: 'danger-full-access' })
        switched = true
      } catch {
        switched = false
      }
    }
    const lines = switched
      ? ['nono layer: off (dsh permission mode danger-full-access; the harness sandbox still applies)']
      : ['nono layer: could not switch to danger-full-access; run /permission danger-full-access']
    if (shells.count > 0) lines.push(`restarted ${shells.count} persistent shell session(s)`)
    lines.push(`saved profile: ${this.storedProfile(session) ?? this.options.defaultProfile} (use /nono <profile> to re-enable)`)
    return { kind: 'success', text: lines.join('\n') }
  }

  /** Close the caller's persistent shells so the next spawn re-confines. */
  async restartShells(agent) {
    const presets = this.ctx.get('agentPresets')
    if (presets === undefined || typeof presets.serviceFor !== 'function') return { known: false, count: 0 }
    let terminals
    try {
      terminals = presets.serviceFor(agent, 'terminals')
    } catch {
      return { known: false, count: 0 }
    }
    if (terminals === undefined || typeof terminals.list !== 'function' || typeof terminals.kill !== 'function') {
      return { known: true, count: 0 }
    }
    let listed
    try {
      listed = terminals.list(agent)
    } catch {
      return { known: true, count: 0 }
    }
    let count = 0
    for (const entry of listed ?? []) {
      try {
        await terminals.kill(agent, entry.sessionId, 'nono profile switch')
        count += 1
      } catch {
        // A shell that died between list and kill does not need restarting.
      }
    }
    return { known: true, count }
  }

  /** Apply the workspace-write preset (sandbox + approval) so nono applies. */
  async enableConfinedMode(agent) {
    const session = agent.session
    const presets = this.ctx.get('permissionPresets')
    const approval = this.ctx.get('approval')
    if (presets !== undefined && Array.isArray(presets.names) && presets.names.includes('workspace-write')) {
      try {
        presets.apply(session, 'workspace-write', (policy) => approval?.setPolicy(agent, policy))
        return 'permission preset workspace-write (non-confined commands are bypassed by /nono off)'
      } catch (error) {
        return `could not switch the permission preset automatically (${messageOf(error)}); run /permission workspace-write or the profile will not apply`
      }
    }
    try {
      session.append('sandbox/mode', { mode: 'workspace-write' })
      return 'sandbox mode switched to workspace-write so the profile applies'
    } catch (error) {
      return `could not switch the sandbox mode automatically (${messageOf(error)}); run /permission workspace-write or the profile will not apply`
    }
  }

  /** The session's effective dsh sandbox mode. */
  effectiveMode(session) {
    const service = this.ctx.get('sandboxPolicy')
    if (service === undefined) return 'workspace-write'
    try {
      return service.resolve({ session })?.mode ?? 'workspace-write'
    } catch {
      return 'workspace-write'
    }
  }

  /** Status text for `/nono` with no argument. */
  statusText(session, current, profiles) {
    const mode = this.effectiveMode(session)
    const active = mode !== 'danger-full-access'
    const readOnly = mode === 'read-only'
    const lines = [
      `nono profile: ${current}${active ? '' : ' (inactive: dsh mode danger-full-access bypasses the sandbox)'}`,
      `dsh sandbox mode: ${mode}${readOnly ? ` (enforcing ${this.options.readOnlyProfile} while read-only)` : ''}`,
    ]
    if (profiles.length > 0) {
      lines.push('available profiles:')
      for (const entry of profiles) lines.push(`  ${entry.name}${entry.description.length > 0 ? ` — ${entry.description}` : ''}`)
    } else {
      lines.push('available profiles: none found (nono or ~/.config/nono/profiles is unavailable)')
    }
    lines.push('usage: /nono <profile> | /nono off | /nono list')
    return lines.join('\n')
  }

  /** Cache-safe runtime context: which nono profile confines this session. */
  renderContext(assembly) {
    const session = assembly?.agent?.session
    if (session === undefined) return ''
    const current = this.storedProfile(session) ?? this.options.defaultProfile
    const mode = this.effectiveMode(session)
    if (mode === 'danger-full-access') {
      return 'Command sandbox: no extra nono profile; dsh is in danger-full-access mode, so shells run with the harness process sandbox only.'
    }
    if (mode === 'read-only') {
      return `Command sandbox: dsh read-only mode; confined shells run through the read-only nono profile "${this.options.readOnlyProfile}" inside the harness process sandbox. The human can leave read-only mode to use the selected profile "${current}".`
    }
    return `Command sandbox: confined shells run through nono profile "${current}" inside the harness process sandbox. The human switches it with /nono <profile>.`
  }

  /** User profiles, preferring nono's own list so built-ins are included. */
  listProfiles() {
    try {
      const text = execFileSync(this.executable('nonoPath'), ['profile', 'list'], {
        encoding: 'utf8',
        timeout: 5000,
        env: { ...process.env, NONO_NO_UPDATE_CHECK: '1' },
        stdio: ['ignore', 'pipe', 'ignore'],
      })
      const parsed = parseProfileList(text)
      if (parsed.length > 0) return parsed
    } catch {
      // fall through to the directory listing
    }
    const profiles = []
    try {
      for (const entry of readdirSync(profileDir()).sort()) {
        if (!entry.endsWith('.json')) continue
        const name = entry.slice(0, -'.json'.length)
        if (!PROFILE_NAME_RE.test(name)) continue
        profiles.push({ name, description: profileDescription(join(profileDir(), entry)) })
      }
    } catch {
      // no user profile directory available
    }
    return profiles
  }
}

function textOr(value, fallback) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : fallback
}

function messageOf(error) {
  return error instanceof Error ? error.message : String(error)
}

/** Best-effort `meta.description` for the directory-listing fallback. */
function profileDescription(file) {
  try {
    const meta = JSON.parse(readFileSync(file, 'utf8'))?.meta
    return typeof meta?.description === 'string' ? meta.description : ''
  } catch {
    return ''
  }
}

export default NonoSandboxProvider
