/**
 * End-to-end check of the MCP stdio server with fake clients: no session, no
 * compositor. Verifies the JSON-RPC surface and that each action emits the
 * exact `viewport msg` argv the dsh plugin emits.
 */
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';
const server = join(dirname(fileURLToPath(import.meta.url)), 'server.mjs');

const temp = mkdtempSync(join(tmpdir(), 'mcp-viewport-test-'));
const log = join(temp, 'viewport.log');
const fakeViewport = join(temp, 'fake-viewport');
const fakeGrim = join(temp, 'fake-grim');

writeFileSync(fakeViewport, [
  `#!${process.execPath}`,
  "const { appendFileSync } = require('node:fs');",
  "appendFileSync(process.env.FAKE_VIEWPORT_LOG, `==call==\\n${process.argv.slice(2).join('\\n')}\\n`);",
  '',
].join('\n'), { mode: 0o755 });
writeFileSync(fakeGrim, [
  `#!${process.execPath}`,
  "const { writeFileSync } = require('node:fs');",
  "writeFileSync(process.argv[2], Buffer.from(process.env.FAKE_PNG_B64, 'base64'));",
  '',
].join('\n'), { mode: 0o755 });

const child = spawn(process.execPath, [server], {
  env: {
    ...process.env,
    MCP_VIEWPORT_BIN: fakeViewport,
    MCP_VIEWPORT_GRIM: fakeGrim,
    MCP_VIEWPORT_SCREENSHOT_DIR: join(temp, 'shots'),
    MCP_VIEWPORT_TIMEOUT_MS: '5000',
    FAKE_VIEWPORT_LOG: log,
    FAKE_PNG_B64: PNG,
  },
  stdio: ['pipe', 'pipe', 'pipe'],
});
let stderr = '';
child.stderr.setEncoding('utf8');
child.stderr.on('data', (chunk) => {
  stderr += chunk;
});

const pending = new Map();
let buffered = '';
child.stdout.setEncoding('utf8');
child.stdout.on('data', (chunk) => {
  buffered += chunk;
  let end;
  while ((end = buffered.indexOf('\n')) >= 0) {
    const line = buffered.slice(0, end);
    buffered = buffered.slice(end + 1);
    if (line.trim() === '') continue;
    const message = JSON.parse(line);
    const resolve = pending.get(message.id);
    if (resolve !== undefined) {
      pending.delete(message.id);
      resolve(message);
    }
  }
});

let nextId = 1;
function rpc(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`timed out waiting for ${method}\n${stderr}`));
    }, 10000);
    pending.set(id, (message) => {
      clearTimeout(timer);
      resolve(message);
    });
    child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  });
}

function notify(method, params = {}) {
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
}

function call(arguments_) {
  return rpc('tools/call', { name: 'viewport', arguments: arguments_ });
}

function textOf(response) {
  assert.equal(response.result.isError, undefined, JSON.stringify(response.result));
  return response.result.content.find((block) => block.type === 'text').text;
}

function hasMessages(logText, messages) {
  return logText.includes(`${['==call==', 'msg', ...messages].join('\n')}\n`);
}

try {
  const init = await rpc('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'test', version: '1' },
  });
  assert.equal(init.result.serverInfo.name, 'mcp-viewport');
  assert.equal(init.result.protocolVersion, '2025-06-18');
  assert.match(init.result.instructions, /screenshot first/i);
  notify('notifications/initialized');

  const list = await rpc('tools/list');
  assert.equal(list.result.tools.length, 1);
  assert.equal(list.result.tools[0].name, 'viewport');
  assert.deepEqual(list.result.tools[0].inputSchema.required, ['action']);

  const shot = await call({ action: 'screenshot' });
  assert.match(textOf(shot), /screenshot of the whole Viewport desktop layout: 1x1 px PNG/);
  const image = shot.result.content.find((block) => block.type === 'image');
  assert.equal(image.mimeType, 'image/png');
  assert.equal(Buffer.from(image.data, 'base64').compare(Buffer.from(PNG, 'base64')), 0);

  assert.match(textOf(await call({ action: 'move', x: 10, y: 20 })), /Moved the pointer to \(10, 20\)/);
  assert.match(textOf(await call({ action: 'click', button: 'right' })), /Clicked the right button at the pointer/);
  assert.match(textOf(await call({ action: 'scroll', dx: -1, dy: 2 })), /Scrolled 2 notches up and 1 notch left/);
  assert.match(textOf(await call({ action: 'type', text: 'Hi\n' })), /Typed 3 characters/);
  assert.match(textOf(await call({ action: 'key', key: 'ctrl+shift+t' })), /Pressed ctrl\+shift\+t/);

  const bad = await call({ action: 'move', x: 10 });
  assert.equal(bad.result.isError, true);
  assert.match(bad.result.content[0].text, /move needs both x and y/);

  const messages = readFileSync(log, 'utf8');
  assert.ok(hasMessages(messages, ['-t', 'input.pointer', '--x', '10', '--y', '20']), messages);
  assert.ok(hasMessages(messages, ['-t', 'input.button', '--button', '273', '--pressed', 'true']), messages);
  assert.ok(hasMessages(messages, ['-t', 'input.button', '--button', '273', '--pressed', 'false']), messages);
  assert.ok(hasMessages(messages, ['-t', 'input.scroll', '--dx', '-1', '--dy', '2']), messages);
  assert.ok(hasMessages(messages, ['-t', 'osk.key', '--keysym', '65293', '--pressed', 'true']), messages);
  assert.ok(hasMessages(messages, ['-t', 'osk.key', '--keysym', '65507', '--pressed', 'true']), messages);
  assert.equal(messages.split('==call==').length - 1, 18);

  process.stderr.write('mcp-viewport: all checks passed\n');
} finally {
  child.kill();
  rmSync(temp, { recursive: true, force: true });
}
