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
const MODELS = (process.env.MATRIX_BRIDGE_MODELS ?? 'deepseek-flash,deepseek-chat,deepseek-reasoner')
  .split(',').map((item) => item.trim()).filter(Boolean)
const DEFAULT_PROVIDER = process.env.MATRIX_BRIDGE_PROVIDER ?? 'deepseek-official'
const MAX_CHUNK = 3800
const DSH_TIMEOUT_MS = 10 * 60 * 1000
const STARTED_AT = Date.now()

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

async function sendText(roomId, eventId, text) {
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
      `/_matrix/client/v3/rooms/${encodeURIComponent(roomId)}/send/m.room.message/${encodeURIComponent(`${eventId}-${index}`)}`,
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

function writeModelPatch(roomId, model) {
  if (!/^[A-Za-z0-9._-]+$/.test(model) || !/^[A-Za-z0-9._-]+$/.test(DEFAULT_PROVIDER)) {
    throw new Error('invalid model or provider name')
  }
  const file = path.join(roomDir(roomId), 'model.patch.yml')
  fs.writeFileSync(
    file,
    `- id: agent-default-model\n  config:\n    provider: ${DEFAULT_PROVIDER}\n    model: ${model}\n`,
    { mode: 0o600 },
  )
  return file
}

function runDsh(roomId, prompt) {
  const args = [
    '--profile', 'headless',
    '--json',
    '--permission-mode', 'danger-full-access',
    '--approval-policy', 'never',
  ]
  const selectedModel = state.rooms[roomId]?.model
  if (selectedModel) args.push('--patch', writeModelPatch(roomId, selectedModel))
  const sessionId = state.rooms[roomId]?.sessionId
  if (sessionId) args.push('--session-id', sessionId)
  args.push(prompt)

  const result = spawnSync(DSH_BIN, args, {
    cwd: roomDir(roomId),
    encoding: 'utf8',
    timeout: DSH_TIMEOUT_MS,
    maxBuffer: 32 * 1024 * 1024,
    env: process.env,
  })
  if (result.error) throw result.error

  let nextSession = sessionId
  let final = ''
  for (const line of (result.stdout ?? '').split('\n')) {
    if (line.startsWith('{') === false) continue
    let record
    try { record = JSON.parse(line) } catch { continue }
    if (record.type === 'session' && typeof record.sessionId === 'string') nextSession = record.sessionId
    if (record.type === 'final' && typeof record.text === 'string') final = record.text
  }
  if (result.status !== 0 && final === '') {
    const detail = (result.stderr ?? '').trim().split('\n').slice(-3).join(' | ')
    throw new Error(`dsh exited ${result.status}: ${detail}`)
  }
  if (nextSession && nextSession !== sessionId) {
    state.rooms[roomId] = { ...(state.rooms[roomId] ?? {}), sessionId: nextSession }
    saveState()
  }
  return final.trim()
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
  '!help — show this help',
  '!new, !clear — start a fresh session',
  '!model [id] — show or switch the model for this room',
  '!models — list available models',
  '!session — show this room’s session id',
  '!status — bridge status',
  '!version — bridge version',
  'Any other message is sent to the Harness agent.',
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
  if (command === 'models') {
    await sendText(roomId, eventId, `Models: ${MODELS.join(', ')}`)
    return
  }
  if (command === 'model') {
    if (argument === '') {
      const current = state.rooms[roomId]?.model ?? MODELS[0]
      await sendText(roomId, eventId, `Models: ${MODELS.join(', ')}\nCurrent: ${current}\n!model <id> switches (starts a fresh session).`)
      return
    }
    if (!MODELS.includes(argument)) {
      await sendText(roomId, eventId, `Unknown model "${argument}". Available: ${MODELS.join(', ')}`)
      return
    }
    state.rooms[roomId] = { ...(state.rooms[roomId] ?? {}), model: argument }
    delete state.rooms[roomId].sessionId
    saveState()
    await sendText(roomId, eventId, `Model set to ${argument}. Next message starts a fresh session.`)
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
  if (command !== '') {
    await sendText(roomId, eventId, `Unknown command !${command}. Send !help for the list.`)
    return
  }

  await sendTyping(roomId)
  const answer = runDsh(roomId, clean)
  await sendText(roomId, eventId, answer === '' ? '(no response)' : answer)
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
