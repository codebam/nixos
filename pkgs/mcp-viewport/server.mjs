/**
 * MCP stdio server for computer use on a live Viewport session.
 *
 * This is the transport half of @codebam/dsh-tool-viewport: the message,
 * keystroke and rendering modules are the pinned plugin's own, so dsh and
 * every other harness drive the seat through exactly the same vocabulary.
 * What differs is the result shape -- MCP carries screenshots as base64 image
 * content instead of dsh's attachment store -- and the absence of any
 * @deepseek-ai peer dependency, which is why the seat and capture live here.
 *
 * Only JSON-RPC goes to stdout; diagnostics, if any, go to stderr.
 */
import { execFile } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { mkdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

import { BUTTON_CODES, buttonMessage, pointerMessage, scrollMessage } from './src/messages.mjs';
import { canonicalChord, chordMessages, typeText } from './src/keys.mjs';
import { screenshotSummary, scrollPhrase, typeSummary } from './src/render.mjs';

const SERVER_NAME = 'mcp-viewport';
const SERVER_VERSION = '0.1.0';
const PROTOCOL_VERSION = '2025-06-18';

const ACTIONS = ['screenshot', 'move', 'click', 'scroll', 'type', 'key'];
const MAX_TYPE_LENGTH = 2000;

function positiveInt(value, fallback) {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

const config = {
  // The control socket only trusts the binary the session runs, so the
  // launcher pins the live system path rather than a different store build.
  executable: process.env.MCP_VIEWPORT_BIN || '/run/current-system/sw/bin/viewport',
  grim: process.env.MCP_VIEWPORT_GRIM || 'grim',
  screenshotDir: process.env.MCP_VIEWPORT_SCREENSHOT_DIR || join(tmpdir(), 'mcp-viewport'),
  timeoutMs: positiveInt(process.env.MCP_VIEWPORT_TIMEOUT_MS, 10000),
};

/**
 * Environment for the two clients. Harnesses launched from a service have no
 * Wayland variables, but the compositor's socket name carries the display it
 * listens on; recovering it here keeps the fix inside this MCP process rather
 * than changing every harness wrapper's environment.
 */
function childEnv() {
  const env = { ...process.env };
  if (!env.XDG_RUNTIME_DIR && typeof process.getuid === 'function') {
    env.XDG_RUNTIME_DIR = `/run/user/${process.getuid()}`;
  }
  if (!env.WAYLAND_DISPLAY && env.XDG_RUNTIME_DIR) {
    try {
      const sockets = readdirSync(env.XDG_RUNTIME_DIR)
        .filter((name) => /^viewport-wayland-.+\.sock$/.test(name))
        .sort();
      if (sockets.length > 0) {
        env.WAYLAND_DISPLAY = sockets[0].slice('viewport-'.length, -'.sock'.length);
      }
    } catch {
      // No runtime dir yet: the client reports the missing session itself.
    }
  }
  return env;
}

function exec(command, args, options) {
  return new Promise((resolve, reject) => {
    execFile(command, args, options, (error, stdout, stderr) => {
      if (error !== null) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

function shellQuote(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function batchScript(command, messages) {
  const lines = [
    'n=0',
    'run() {',
    '  n=$((n + 1))',
    `  ${command.join(' ')} "$@" || { s=$?; echo "viewport: message $n of ${messages.length} was refused (exit $s)" >&2; exit $s; }`,
    '}',
    ...messages.map((message) => `run ${message.map(shellQuote).join(' ')}`),
  ];
  return `${lines.join('\n')}\n`;
}

function aborted() {
  const error = new Error('tool call aborted');
  error.name = 'AbortError';
  return error;
}

function shape(error, executable, timeout) {
  if (error.name === 'AbortError') return aborted();
  if (error.code === 'ENOENT') {
    return new Error(`cannot run \`${executable}\`: ${error.message} — MCP_VIEWPORT_BIN/MCP_VIEWPORT_GRIM must name the Viewport and grim clients`);
  }
  if (error.killed) {
    return new Error(`\`${executable}\` did not answer within ${timeout}ms; is a Viewport session running?`);
  }
  const stderr = typeof error.stderr === 'string' ? error.stderr.trim() : '';
  if (stderr.length > 0) return new Error(stderr);
  return new Error(`\`${executable}\` exited ${error.code ?? 'unnamed'} with no message on stderr`);
}

class Seat {
  #base;

  constructor(socket) {
    this.#base = socket === undefined ? ['msg'] : ['msg', '--socket', socket];
  }

  timeoutFor(count) {
    if (count <= 1) return config.timeoutMs;
    return Math.max(config.timeoutMs, Math.min(count * 500 + 3000, 300_000));
  }

  async run(messages, signal) {
    if (messages.length === 0) return;
    if (signal?.aborted) throw aborted();
    const timeout = this.timeoutFor(messages.length);
    const options = {
      timeout,
      signal,
      env: childEnv(),
      maxBuffer: 16 * 1024 * 1024,
      encoding: 'utf8',
    };
    let command = config.executable;
    let args = [...this.#base, ...messages[0]];
    if (messages.length > 1) {
      command = 'sh';
      args = ['-c', batchScript([config.executable, ...this.#base].map(shellQuote), messages)];
    }
    try {
      await exec(command, args, options);
    } catch (error) {
      throw shape(error, command === 'sh' ? config.executable : command, timeout);
    }
  }
}

function shotName(now = new Date()) {
  const pad = (value, width = 2) => String(value).padStart(width, '0');
  const stamp = [
    now.getFullYear(), pad(now.getMonth() + 1), pad(now.getDate()), '-',
    pad(now.getHours()), pad(now.getMinutes()), pad(now.getSeconds()), pad(now.getMilliseconds(), 3),
  ].join('');
  return `viewport-${stamp}-${Math.random().toString(36).slice(2, 6)}.png`;
}

function pngSize(data) {
  const png = Buffer.isBuffer(data) ? data : Buffer.from(data);
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (png.length < 24 || !png.subarray(0, 8).equals(signature) || png.subarray(12, 16).toString('latin1') !== 'IHDR') {
    throw new Error('the capture is not a PNG — grim did not write an image');
  }
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

async function capture(signal) {
  await mkdir(config.screenshotDir, { recursive: true });
  const path = join(config.screenshotDir, shotName());
  try {
    await exec(config.grim, [path], {
      timeout: config.timeoutMs,
      signal,
      env: childEnv(),
      maxBuffer: 16 * 1024 * 1024,
      encoding: 'utf8',
    });
  } catch (error) {
    throw shape(error, config.grim, config.timeoutMs);
  }
  const data = await readFile(path);
  const { width, height } = pngSize(data);
  return { path, data, width, height };
}

function assertFinite(value, name) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`${name} must be a finite number, got ${JSON.stringify(value)}`);
  }
}

function assertNotches(value, name) {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new Error(`${name} must be a whole number of notches, got ${JSON.stringify(value)}`);
  }
}

function validateArgs(args) {
  if (args === null || typeof args !== 'object' || Array.isArray(args)) {
    throw new Error('the viewport tool takes an object of arguments');
  }
  if (typeof args.action !== 'string' || !ACTIONS.includes(args.action)) {
    throw new Error(`unknown action ${JSON.stringify(args.action)} — expected one of: ${ACTIONS.join(', ')}`);
  }
  const hasX = args.x !== undefined;
  const hasY = args.y !== undefined;
  const pointPair = (use) => {
    if (hasX !== hasY) throw new Error(`${use} takes x and y together — give both, or neither`);
    if (hasX) {
      assertFinite(args.x, 'x');
      assertFinite(args.y, 'y');
    }
  };
  switch (args.action) {
    case 'screenshot':
      break;
    case 'move':
      if (!hasX || !hasY) throw new Error('move needs both x and y — the layout coordinates to put the pointer at');
      assertFinite(args.x, 'x');
      assertFinite(args.y, 'y');
      break;
    case 'click':
      pointPair('click');
      if (args.button !== undefined && !(args.button in BUTTON_CODES)) {
        throw new Error(`unknown button ${JSON.stringify(args.button)} — the buttons are left, right and middle`);
      }
      break;
    case 'scroll': {
      const dx = args.dx ?? 0;
      const dy = args.dy ?? 0;
      assertNotches(dx, 'dx');
      assertNotches(dy, 'dy');
      if (dx === 0 && dy === 0) {
        throw new Error('scroll needs dx or dy — the wheel notches to turn, positive up and right');
      }
      pointPair('scroll');
      break;
    }
    case 'type': {
      if (typeof args.text !== 'string' || args.text.length === 0) {
        throw new Error('type needs text — the string to type');
      }
      if ([...args.text].length > MAX_TYPE_LENGTH) {
        throw new Error(`type takes at most ${MAX_TYPE_LENGTH} characters per call; split the text into a few calls`);
      }
      break;
    }
    case 'key':
      if (typeof args.key !== 'string' || args.key.trim().length === 0) {
        throw new Error('key needs the key or chord to press, like `Return`, `Escape` or `ctrl+c`');
      }
      break;
  }
}

const DESCRIPTION = [
  'See and drive the Viewport desktop this harness runs on: take a screenshot, move the pointer, click, turn the wheel, type text, and press keys.',
  '',
  'Input goes into the real session a person is sitting at — the pointer moves on their screen and typing lands in whatever has focus — so look before you act: `screenshot` first, act in small steps, screenshot again to check.',
  '',
  'Coordinates are layout pixels on the whole desktop: the same pixels as the screenshot, (0, 0) at its top-left corner. `scroll` counts wheel notches, positive up (`dy`) and right (`dx`); one notch is one detent of a wheel.',
  '',
  'Actions: `screenshot` captures the whole desktop and returns the image; `move` puts the pointer at (x, y); `click` presses and releases a button (`left`, `right`, `middle`) at the pointer, or at (x, y) in one step; `scroll` turns the wheel by (dx, dy) notches, optionally moving to (x, y) first; `type` types text, with `\\n` for Return; `key` presses one named key (`Return`, `Escape`, `Tab`, arrows, `F5`, …) or a `+` chord (`ctrl+c`, `ctrl+shift+t`).',
  '',
  'This needs a running Viewport session; a refused or unanswered message is reported as an error, in the client\'s own words.',
].join('\n');

const INSTRUCTIONS = [
  'The viewport tool drives the real desktop this harness runs on: its screenshots are the live screen and its clicks, wheel turns and keystrokes land in the session a person is sitting at.',
  'Screenshot first, act in small steps, screenshot again to check, and keep the user told what you are about to do to their screen.',
].join(' ');

const TOOL = {
  name: 'viewport',
  description: DESCRIPTION,
  inputSchema: {
    type: 'object',
    additionalProperties: false,
    required: ['action'],
    properties: {
      action: {
        type: 'string',
        enum: [...ACTIONS],
        description: 'Which action to take.',
      },
      x: {
        type: 'number',
        description: 'Pointer x in layout pixels: required for `move`; optional for `click` and `scroll`, which move to it first.',
      },
      y: {
        type: 'number',
        description: 'Pointer y in layout pixels, beside x.',
      },
      button: {
        type: 'string',
        enum: Object.keys(BUTTON_CODES),
        description: 'The mouse button for `click`; defaults to left.',
      },
      dx: {
        type: 'number',
        description: 'Wheel notches to the right (negative: left), for `scroll`.',
      },
      dy: {
        type: 'number',
        description: 'Wheel notches up (negative: down), for `scroll`.',
      },
      text: {
        type: 'string',
        description: 'The text to type, for `type`. Newlines are Return and tabs are Tab.',
      },
      key: {
        type: 'string',
        description: 'The key or chord to press, for `key`: a name like `Return`/`Escape`/`F5`, a single character, or modifiers joined with `+` (`ctrl+alt+t`).',
      },
    },
  },
};

const seat = new Seat(process.env.MCP_VIEWPORT_SOCKET);

async function callTool(params, signal) {
  const args = params?.arguments;
  validateArgs(args);
  let text;
  switch (args.action) {
    case 'screenshot': {
      const shot = await capture(signal);
      text = screenshotSummary({
        path: shot.path,
        width: shot.width,
        height: shot.height,
        bytes: shot.data.length,
      });
      return {
        content: [
          { type: 'text', text },
          { type: 'image', data: shot.data.toString('base64'), mimeType: 'image/png' },
        ],
      };
    }
    case 'move': {
      await seat.run([pointerMessage(args.x, args.y)], signal);
      text = `Moved the pointer to (${args.x}, ${args.y}).`;
      break;
    }
    case 'click': {
      const button = args.button ?? 'left';
      const messages = [];
      if (args.x !== undefined) messages.push(pointerMessage(args.x, args.y));
      messages.push(buttonMessage(BUTTON_CODES[button], true), buttonMessage(BUTTON_CODES[button], false));
      await seat.run(messages, signal);
      const where = args.x === undefined ? ' at the pointer' : ` at (${args.x}, ${args.y})`;
      text = `Clicked the ${button} button${where}.`;
      break;
    }
    case 'scroll': {
      const dx = args.dx ?? 0;
      const dy = args.dy ?? 0;
      const messages = [];
      if (args.x !== undefined) messages.push(pointerMessage(args.x, args.y));
      messages.push(scrollMessage(dx, dy));
      await seat.run(messages, signal);
      const at = args.x === undefined ? '' : ` at (${args.x}, ${args.y})`;
      text = `Scrolled ${scrollPhrase(dx, dy)}${at}.`;
      break;
    }
    case 'type': {
      await seat.run(typeText(args.text), signal);
      text = typeSummary(args.text);
      break;
    }
    case 'key': {
      await seat.run(chordMessages(args.key), signal);
      text = `Pressed ${canonicalChord(args.key)}.`;
      break;
    }
  }
  return { content: [{ type: 'text', text }] };
}

const controllers = new Map();

async function handle(message) {
  if (message === null || typeof message !== 'object' || message.jsonrpc !== '2.0') return null;

  if (message.method === 'notifications/cancelled') {
    const id = message.params?.requestId;
    const controller = controllers.get(id);
    if (controller !== undefined) {
      controller.abort();
      controllers.delete(id);
    }
    return null;
  }
  if (message.id === undefined || typeof message.method !== 'string') return null;

  const reply = (result) => ({ jsonrpc: '2.0', id: message.id, result });
  try {
    switch (message.method) {
      case 'initialize':
        return reply({
          protocolVersion: typeof message.params?.protocolVersion === 'string'
            ? message.params.protocolVersion
            : PROTOCOL_VERSION,
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
          instructions: INSTRUCTIONS,
        });
      case 'ping':
        return reply({});
      case 'tools/list':
        return reply({ tools: [TOOL] });
      case 'tools/call': {
        const controller = new AbortController();
        controllers.set(message.id, controller);
        try {
          return reply(await callTool(message.params, controller.signal));
        } catch (error) {
          const text = error instanceof Error ? error.message : String(error);
          return reply({ content: [{ type: 'text', text }], isError: true });
        } finally {
          controllers.delete(message.id);
        }
      }
      case 'resources/list':
        return reply({ resources: [] });
      case 'prompts/list':
        return reply({ prompts: [] });
      default:
        return {
          jsonrpc: '2.0',
          id: message.id,
          error: { code: -32601, message: `Method not found: ${message.method}` },
        };
    }
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return {
      jsonrpc: '2.0',
      id: message.id,
      error: { code: -32603, message: `Internal error: ${detail}` },
    };
  }
}

function write(message) {
  if (message === null || message === undefined) return;
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function processLine(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  if (Array.isArray(message)) {
    const responses = await Promise.all(message.map(handle));
    const batch = responses.filter((response) => response !== null);
    if (batch.length > 0) write(batch);
  } else {
    write(await handle(message));
  }
}

process.stdout.on('error', (error) => {
  if (error.code === 'EPIPE') process.exit(0);
  throw error;
});

const input = createInterface({ input: process.stdin, crlfDelay: Infinity, terminal: false });
let queue = Promise.resolve();
input.on('line', (line) => {
  queue = queue.then(() => processLine(line)).catch((error) => {
    process.stderr.write(`mcp-viewport: ${error instanceof Error ? error.stack : String(error)}\n`);
  });
});
