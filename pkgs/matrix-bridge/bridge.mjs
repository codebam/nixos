#!/usr/bin/env node
// Matrix appservice -> DeepSeek Harness bridge.
//
// matrix-workers pushes every matching Matrix event as an appservice
// transaction (PUT /_matrix/app/v1/transactions/:txnId). This service accepts
// those pushes, keeps one DSH headless session per room, and posts the final
// answer back to the room over the Matrix client API. No /sync loop, so no
// long-poll Durable Object time on the homeserver.
//
// Secrets are read from files mounted by sops-nix; only non-secret settings
// live in the systemd unit.

import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const PORT = Number(process.env.MATRIX_BRIDGE_PORT ?? 3081)
const HOMESERVER = (process.env.MATRIX_BRIDGE_HOMESERVER ?? 'https://codebam.ca').replace(/\/$/, '')
const STATE_DIR = process.env.MATRIX_BRIDGE_STATE_DIR ?? path.join(process.env.HOME ?? '.', '.local/share/matrix-bridge')
const DSH_BIN = process.env.MATRIX_BRIDGE_DSH ?? 'dsh'
const HS_TOKEN_FILE = process.env.MATRIX_BRIDGE_HS_TOKEN_FILE
const BOT_TOKEN_FILE = process.env.MATRIX_BRIDGE_BOT_TOKEN_FILE
const BOT_USER = process.env.MATRIX_BRIDGE_BOT_USER ?? '@dshbot:codebam.ca'
const ALLOWED_USER = process.env.MATRIX_BRIDGE_ALLOWED_USER ?? '@codebam:codebam.ca'
const YQ = process.env.MATRIX_BRIDGE_YQ
const SETTINGS_FILE = process.env.MATRIX_BRIDGE_SETTINGS_FILE
const OPENCODE_MODELS_FILE = process.env.MATRIX_BRIDGE_MODELS_FILE
const DEFAULT_PROVIDER = process.env.MATRIX_BRIDGE_PROVIDER ?? 'deepseek-official'
const MAX_CHUNK = 3800
const DSH_TIMEOUT_MS = 10 * 60 * 1000
const STARTED_AT = Date.now()
const PERSONA = [
  'You are a helpful assistant talking to the user over Matrix chat.',
  'Keep replies concise and readable in a chat client: short paragraphs, no walls of text, no Markdown tables.',
  'When a task needs several updates, send them as separate short messages rather than one long message.',
  'Do not repeat the user’s question back to them.',
].join(' ')

if (!HS_TOKEN_FILE || !BOT_TOKEN_FILE) {
  console.error('matrix-bridge: MATRIX_BRIDGE_HS_TOKEN_FILE and MATRIX_BRIDGE_BOT_TOKEN_FILE are required')
  process.exit(2)
}

function readSecret(file) {
  return fs.readFileSync(file, 'utf8').trim()
}

const hsToken = readSecret(HS_TOKEN_FILE)
const botToken = readSecret(BOT_TOKEN_FILE)
const stateFile = path.join(STATE_DIR, 'state.json')

function readJsonFile(file, fallback) {
  if (!file || !fs.existsSync(file)) return fallback
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return fallback
  }
}

// The dsh web profile's provider routes live in ~/.dsh/settings.yaml. yq
// converts that YAML into the JSON we need both for listing models and for
// mounting the same routes into the headless run when a model is selected.
function loadProviders() {
  if (!YQ || !SETTINGS_FILE || !fs.existsSync(SETTINGS_FILE)) return {}
  const result = spawnSync(YQ, [ '-o=json', '.llm-pi-ai.providers', SETTINGS_FILE ], {
    encoding: 'utf8',
    timeout: 10_000,
  })
  if (result.status !== 0) {
    console.error('matrix-bridge: could not read provider catalog:', (result.stderr ?? '').trim().slice(0, 300))
    return {}
  }
  try {
    const parsed = JSON.parse(result.stdout)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

const providers = loadProviders()
const catalog = []
for (const [provider, config] of Object.entries(providers)) {
  if (!Array.isArray(config?.models)) continue
  for (const model of config.models) {
    if (typeof model?.id !== 'string') continue
    catalog.push({ id: `${provider}/${model.id}`, provider, model: model.id, name: model.name ?? model.id })
  }
}
for (const model of readJsonFile(OPENCODE_MODELS_FILE, [])) {
  if (typeof model?.id !== 'string') continue
  catalog.push({ id: `opencode-go/${model.id}`, provider: 'opencode-go', model: model.id, name: model.name ?? model.id })
}
for (const model of [ 'deepseek-flash', 'deepseek-chat', 'deepseek-reasoner' ]) {
  catalog.push({ id: `${DEFAULT_PROVIDER}/${model}`, provider: DEFAULT_PROVIDER, model, name: model })
}
const seenModels = new Set()
const MODELS = catalog.filter((entry) => {
  if (seenModels.has(entry.id)) return false
  seenModels.add(entry.id)
  return true
})
console.log(`matrix-bridge: ${MODELS.length} models available`)

fs.mkdirSync(STATE_DIR, { recursive: true })
let state = { transactions: [], events: [], rooms: {} }
try {
  const loaded = JSON.parse(fs.readFileSync(stateFile, 'utf8'))
  if (loaded && typeof loaded === 'object') {
    state = {
      transactions: Array.isArray(loaded.transactions) ? loaded.transactions : [],
      events: Array.isArray(loaded.events) ? loaded.events : [],
      rooms: loaded.rooms && typeof loaded.rooms === 'object' ? loaded.rooms : {},
    }
  }
} catch {
  // Fresh state.
}

function saveState() {
  const tmp = `${stateFile}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2), { mode: 0o600 })
  fs.renameSync(tmp, stateFile)
}

function remember(list, value, limit = 5000) {
  if (list.includes(value)) return false
  list.push(value)
  if (list.length > limit) list.splice(0, list.length - limit)
  return true
}

async function matrix(method, apiPath, body) {
  const response = await fetch(`${HOMESERVER}${apiPath}`, {
    method,
    headers: {
      Authorization: `Bearer ${botToken}`,
      'Content-Type': 'application/json',
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(30_000),
  })
  if (!response.ok) {
    const detail = await response.text().catch(() => '')
    throw new Error(`Matrix ${method} ${apiPath}: ${response.status} ${detail.slice(0, 300)}`)
  }
  return response.json().catch(() => ({}))
}

async function sendTyping(roomId) {
  await matrix(
    'PUT',
    `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/typing/${encodeURIComponent(BOT_USER)}`,
    { typing: true, timeout: 60_000 },
  ).catch(() => undefined)
}

async function sendText(roomId, eventId, text, sequence = 0) {
  const chunks = []
  let rest = text.trim()
  while (rest.length > MAX_CHUNK) {
    let cut = rest.lastIndexOf('\n', MAX_CHUNK)
    if (cut < MAX_CHUNK / 2) cut = MAX_CHUNK
    chunks.push(rest.slice(0, cut))
    rest = rest.slice(cut).trimStart()
  }
  if (rest !== '') chunks.push(rest)
  for (const [index, chunk] of chunks.entries()) {
    await matrix(
      'PUT',
      `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${encodeURIComponent(`${eventId}-${sequence}-${index}`)}`,
      { msgtype: 'm.text', body: chunk },
    )
  }
}

function roomDir(roomId) {
  const safe = roomId.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 160)
  const dir = path.join(STATE_DIR, 'rooms', safe)
  fs.mkdirSync(dir, { recursive: true })
  return dir
}

function writeRunPatch(roomId, selected) {
  // The persona keeps answers chat-sized and asks the agent to use several
  // messages when a task has several parts.
  const patch = [
    {
      id: 'matrix-chat-persona',
      name: '@deepseek-ai/dsh-persona',
      config: {
        prefix: PERSONA,
        complete: true,
        includeRuntimeContext: false,
      },
    },
  ]
  if (selected?.model) {
    const provider = selected.provider ?? DEFAULT_PROVIDER
    if (!/^[A-Za-z0-9._:/-]+$/.test(provider) || !/^[A-Za-z0-9._:-]+$/.test(selected.model)) {
      throw new Error('invalid model or provider name')
    }
    patch.unshift({
      id: 'llm-pi-ai',
      name: '@deepseek-ai/dsh-llm-pi-ai',
      config: { providers },
    })
    patch.push({
      id: 'agent-default-model',
      config: { provider, model: selected.model },
    })
  }
  let body
  if (YQ) {
    const result = spawnSync(YQ, [ '-p=json', '-o=yaml' ], {
      input: JSON.stringify(patch),
      encoding: 'utf8',
      timeout: 10_000,
    })
    if (result.status === 0) body = result.stdout
  }
  if (!body) {
    // Fallback still applies the persona (and the model selection when set),
    // but cannot mount the full provider catalog without yq.
    body = `- id: matrix-chat-persona\n  name: '@deepseek-ai/dsh-persona'\n  config:\n    prefix: ${JSON.stringify(PERSONA)}\n    complete: true\n    includeRuntimeContext: false\n`
    if (selected?.model) {
      body += `- id: agent-default-model\n  config:\n    provider: ${selected.provider ?? DEFAULT_PROVIDER}\n    model: ${selected.model}\n`
    }
  }
  const file = path.join(roomDir(roomId), 'run.patch.yml')
  fs.writeFileSync(file, body, { mode: 0o600 })
  return file
}

function runDsh(roomId, prompt) {
  // Launcher flags (--profile, --patch) must precede the headless app's own
  // flags; otherwise the app rejects them as unknown options.
  const launcherArgs = [ '--profile', 'headless' ]
  const appArgs = [ '--json', '--permission-mode', 'danger-full-access', '--approval-policy', 'never' ]
  const selected = state.rooms[roomId]
  launcherArgs.push('--patch', writeRunPatch(roomId, selected))
  const sessionId = state.rooms[roomId]?.sessionId
  if (sessionId) appArgs.push('--session-id', sessionId)
  appArgs.push(prompt)
  const args = [ ...launcherArgs, ...appArgs ]

  const result = spawnSync(DSH_BIN, args, {
    cwd: roomDir(roomId),
    encoding: 'utf8',
    timeout: DSH_TIMEOUT_MS,
    maxBuffer: 32 * 1024 * 1024,
    env: process.env,
  })
  if (result.error) throw result.error

  let nextSession = sessionId
  const messages = []
  let final = ''
  for (const line of (result.stdout ?? '').split('\n')) {
    if (line.startsWith('{') === false) continue
    let record
    try { record = JSON.parse(line) } catch { continue }
    if (record.type === 'session' && typeof record.sessionId === 'string') nextSession = record.sessionId
    if (record.type === 'text' && typeof record.text === 'string' && record.text.trim() !== '') {
      messages.push(record.text.trim())
    }
    if (record.type === 'final' && typeof record.text === 'string') final = record.text.trim()
  }
  // The final record usually restates the last streamed text block; only add
  // it when it carries something new.
  if (final !== '' && messages[messages.length - 1] !== final) messages.push(final)
  if (result.status !== 0 && final === '') {
    const detail = (result.stderr ?? '').trim().split('\n').slice(-3).join(' | ')
    const wireErrors = (result.stdout ?? '').split('\n')
      .filter((line) => line.startsWith('{'))
      .map((line) => {
        try { return JSON.parse(line) } catch { return null }
      })
      .filter((record) => record?.type === 'error')
      .map((record) => record.message)
      .join(' | ')
    throw new Error(`dsh exited ${result.status}: ${detail || wireErrors || 'no detail'}`)
  }
  if (nextSession && nextSession !== sessionId) {
    state.rooms[roomId] = { ...(state.rooms[roomId] ?? {}), sessionId: nextSession }
    saveState()
  }
  return messages
}

async function botJoined(roomId) {
  try {
    const member = await matrix(
      'GET',
      `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/state/m.room.member/${encodeURIComponent(BOT_USER)}`,
    )
    return member?.membership === 'join'
  } catch {
    return false
  }
}

const HELP_TEXT = [
  '!prompt <text> — send a prompt to the agent (alias: !p, !ask)',
  '!help — show this help',
  '!new, !clear — start a fresh session',
  '!model [id] — show or switch the model for this room',
  '!models — list available models',
  '!session — show this room’s session id',
  '!status — bridge status',
  '!version — bridge version',
  'Plain messages are ignored; use !prompt to send a prompt.',
  'All commands also accept the / prefix.',
].join('\n')

async function handleMessage(roomId, eventId, sender, text) {
  if (sender === BOT_USER) return
  // Single-user gate: nobody else can drive this bridge, in any room.
  if (sender !== ALLOWED_USER) return
  // The appservice's room namespace is broad, so it sees events from every
  // room on the homeserver. Only answer where the bot was invited and joined.
  if (!(await botJoined(roomId))) return

  const clean = text.trim()
  if (clean === '') return
  // Accept both ! and / prefixes for every command.
  const commandMatch = /^([!/])([a-z]+)\b(.*)$/i.exec(clean)
  const command = commandMatch ? commandMatch[2].toLowerCase() : ''
  const argument = commandMatch ? commandMatch[3].trim() : ''

  if (command === 'help') {
    await sendText(roomId, eventId, HELP_TEXT)
    return
  }
  if (command === 'new' || command === 'clear' || command === 'start') {
    delete state.rooms[roomId]
    saveState()
    await sendText(roomId, eventId, 'Started a fresh session.')
    return
  }
  const modelList = MODELS.map((entry) => `${entry.id}${entry.name && entry.name !== entry.model ? ` — ${entry.name}` : ''}`).join('\n')
  const currentSelection = state.rooms[roomId]?.model
    ? `${state.rooms[roomId].provider ?? DEFAULT_PROVIDER}/${state.rooms[roomId].model}`
    : `default (${DEFAULT_PROVIDER}/deepseek-flash)`
  if (command === 'models') {
    await sendText(roomId, eventId, `Available models:\n${modelList}`)
    return
  }
  if (command === 'model') {
    if (argument === '') {
      await sendText(roomId, eventId, `Current: ${currentSelection}\n\nAvailable models:\n${modelList}\n\n!model <provider/model> switches (starts a fresh session).`)
      return
    }
    let selected = MODELS.find((entry) => entry.id === argument)
    if (!selected) {
      const matches = MODELS.filter((entry) => entry.model === argument)
      if (matches.length === 1) selected = matches[0]
    }
    if (!selected) {
      await sendText(roomId, eventId, `Unknown model "${argument}". Send !models for the list.`)
      return
    }
    state.rooms[roomId] = { ...(state.rooms[roomId] ?? {}), provider: selected.provider, model: selected.model }
    delete state.rooms[roomId].sessionId
    saveState()
    await sendText(roomId, eventId, `Model set to ${selected.id}. Next !prompt starts a fresh session.`)
    return
  }
  if (command === 'session') {
    const sessionId = state.rooms[roomId]?.sessionId
    await sendText(roomId, eventId, sessionId ? `Session: ${sessionId}` : 'No session yet; send a message to start one.')
    return
  }
  if (command === 'status') {
    const uptime = Math.round((Date.now() - STARTED_AT) / 1000)
    await sendText(
      roomId,
      eventId,
      `Bridge: running\nHomeserver: ${HOMESERVER}\nBot: ${BOT_USER}\nAllowed user: ${ALLOWED_USER}\nActive rooms: ${Object.keys(state.rooms).length}\nUptime: ${uptime}s`,
    )
    return
  }
  if (command === 'version') {
    await sendText(roomId, eventId, 'matrix-bridge 1.0 (appservice webhook)')
    return
  }
  if (command === 'prompt' || command === 'p' || command === 'ask') {
    if (argument === '') {
      await sendText(roomId, eventId, 'Usage: !prompt <text>')
      return
    }
    await sendTyping(roomId)
    const answers = runDsh(roomId, argument)
    if (answers.length === 0) {
      await sendText(roomId, eventId, '(no response)')
    } else {
      for (const [index, answer] of answers.entries()) await sendText(roomId, eventId, answer, index + 1)
    }
    return
  }
  if (command !== '') {
    await sendText(roomId, eventId, `Unknown command !${command}. Send !help for the list.`)
  }
  // Plain room chatter is intentionally ignored: only !commands drive the bot.
}

const queue = []
let draining = false
async function drain() {
  if (draining) return
  draining = true
  while (queue.length > 0) {
    const item = queue.shift()
    try {
      if (item.kind === 'join') {
        await matrix('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(item.roomId)}/join`, {})
      } else {
        await handleMessage(item.roomId, item.eventId, item.sender, item.text)
      }
    } catch (error) {
      console.error('matrix-bridge: message failed:', error?.stack ?? error)
      await sendText(item.roomId, `${item.eventId}-error`, `Bridge error: ${String(error?.message ?? error).slice(0, 300)}`).catch(() => undefined)
    }
  }
  draining = false
}

function acceptTransaction(txnId, body) {
  if (!remember(state.transactions, String(txnId))) return
  const events = Array.isArray(body?.events) ? body.events : []
  for (const event of events) {
    // Private rooms require an invite before the bot can read or answer.
    if (event?.type === 'm.room.member' && event?.state_key === BOT_USER && event?.content?.membership === 'invite') {
      queue.push({ kind: 'join', roomId: event.room_id })
      continue
    }
    if (event?.type !== 'm.room.message') continue
    if (event?.content?.msgtype !== 'm.text') continue
    const eventId = event.event_id
    const roomId = event.room_id
    const sender = event.sender
    const text = event.content.body
    if (typeof eventId !== 'string' || typeof roomId !== 'string' || typeof sender !== 'string' || typeof text !== 'string') continue
    if (!remember(state.events, eventId)) continue
    queue.push({ roomId, eventId, sender, text })
  }
  saveState()
  void drain()
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${PORT}`)
  const authorized = req.headers.authorization === `Bearer ${hsToken}`
  const reply = (status, body) => {
    res.writeHead(status, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify(body))
  }

  if (url.pathname === '/healthz') return reply(200, { ok: true })

  if (!authorized) return reply(401, { errcode: 'M_MISSING_TOKEN', error: 'Missing or invalid AS token' })

  if (url.pathname.startsWith('/_matrix/app/v1/transactions/')) {
    if (req.method !== 'PUT' && req.method !== 'POST') return reply(405, { errcode: 'M_UNRECOGNIZED', error: 'Method not allowed' })
    const txnId = decodeURIComponent(url.pathname.split('/').pop() ?? '')
    const chunks = []
    req.on('data', (chunk) => {
      chunks.push(chunk)
      if (chunks.length > 100) req.destroy()
    })
    req.on('end', () => {
      try {
        acceptTransaction(txnId, JSON.parse(Buffer.concat(chunks).toString('utf8')))
        reply(200, {})
      } catch (error) {
        console.error('matrix-bridge: bad transaction:', error)
        reply(400, { errcode: 'M_BAD_JSON', error: 'Invalid transaction body' })
      }
    })
    return
  }

  // Application-service namespace queries from the homeserver.
  if (url.pathname.startsWith('/_matrix/app/v1/users/')) {
    const userId = decodeURIComponent(url.pathname.split('/').pop() ?? '')
    return reply(userId === BOT_USER ? 200 : 404, {})
  }
  if (url.pathname.startsWith('/_matrix/app/v1/rooms/')) return reply(404, { errcode: 'M_NOT_FOUND', error: 'Unknown alias' })
  return reply(404, { errcode: 'M_UNRECOGNIZED', error: 'Unknown endpoint' })
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`matrix-bridge: listening on 127.0.0.1:${PORT}`)
})
