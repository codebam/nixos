#!/usr/bin/env node
// bake.mjs — render the oled wallpaper shader to files, and check them.
//
// The art lives in live.html and nowhere else. This drives one headless
// Chromium over the DevTools protocol, calls window.__render for each frame,
// and writes what comes back. Running the page instead of reimplementing the
// shader in JS or Python is the whole point: a baked still and a live frame
// cannot drift apart, because it is the same draw call.
//
//   node bake.mjs selftest [--w 640 --h 180]
//   node bake.mjs pool     [--out pool --w 5120 --h 1440 --count 24 --jobs 4]
//   node bake.mjs verify   [--dir pool]
//   node bake.mjs sheet    [--dir pool --out preview.png]
//
// flags: --w --h --count --jobs --out --dir --format webp|png --quality
//        --dither --dither-mode ign|bayer --apl-max --peak --oct
//        --chrome <path> --url <live.html> --timeout N

import { spawn } from "node:child_process";
import { mkdir, writeFile, readFile, readdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import net from "node:net";
import path from "node:path";
import os from "node:os";

const HERE = path.dirname(new URL(import.meta.url).pathname);
const STARTED = Date.now();

// ---------------------------------------------------------------------- args
const argv = process.argv.slice(2);
const cmd = argv[0] && !argv[0].startsWith("--") ? argv[0] : "selftest";
function flag(name, dflt){
  const i = argv.indexOf("--" + name);
  if (i === -1) return dflt;
  const v = argv[i+1];
  return (v === undefined || v.startsWith("--")) ? true : v;
}
const W       = parseInt(flag("w", 640), 10);
const H       = parseInt(flag("h", 180), 10);
const OUT     = String(flag("out", cmd === "pool" ? "pool" : "preview.png"));
const DIR     = String(flag("dir", "pool"));
const COUNT   = parseInt(flag("count", 24), 10);
const JOBS    = Math.max(1, parseInt(flag("jobs", 2), 10));
const FORMAT  = String(flag("format", "webp"));
// webp at quality 1.0 is lossless, and measured 2-3x smaller than png for this
// art; `verify --diff` re-renders and proves the files are pixel-exact rather
// than trusting that.  Do not lower it: q<=0.98 measured 17-18/255 of error on
// the aurora frame, which is a quantiser step larger than the 1-LSB dither it
// then throws away, and that is exactly how a near-black gradient bands.
const QUALITY = parseFloat(flag("quality", 1.0));
const DITHER  = parseFloat(flag("dither", 1));
// Same dither as the live page by default: the point of baking from the page is
// that the still and the live frame are the same picture.  `bayer` compresses
// ~10% smaller and is there as a choice, not as the default.
const DITHER_MODE = String(flag("dither-mode", "ign")) === "bayer" ? 1 : 0;
// Ceiling on the mean fraction of full drive a pool frame may emit. A frame at
// three times the drive of its neighbours is a frame that ages the panel
// faster than they do, and which moment a scene is sampled at decides that
// more than the scene does -- so the sampler resamples the outliers.
const APL_MAX = parseFloat(flag("apl-max", 0.055));
const PEAK    = parseFloat(flag("peak", 0.72));
const OCT     = parseInt(flag("oct", 5), 10);
const CHROME  = String(flag("chrome", process.env.CHROME || "google-chrome"));
const LIVE    = path.resolve(String(flag("url", path.join(HERE, "live.html"))));
const TIMEOUT = parseFloat(flag("timeout", 300))*1000;

const EXT = FORMAT === "png" ? "png" : "webp";
const MIME = FORMAT === "png" ? "image/png" : "image/webp";

const MODES = ["silk","aurora","nebula","orbit","ripple","bands","whisper"];
const PALETTES = ["dragon","orchid","ice","ember","synthwave","mono"];

// ------------------------------------------------------------------ chromium
function freePort(){
  return new Promise((res, rej) => {
    const s = net.createServer();
    s.on("error", rej);
    s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => res(p)); });
  });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function launch(){
  const port = await freePort();
  const dir = await mkdtemp();
  const proc = spawn(CHROME, [
    "--headless=new",
    "--no-sandbox", "--disable-gpu-sandbox", "--disable-dev-shm-usage",
    "--enable-unsafe-swiftshader",
    // A wallpaper is shown next to everything else on the desk: pin the colour
    // profile and the scale so what is baked is what the compositor paints.
    "--force-color-profile=srgb",
    "--force-device-scale-factor=1",
    "--hide-scrollbars", "--mute-audio",
    // Reading back a drawn file:// image taints the canvas without this, and
    // the verify pass is exactly that.
    "--allow-file-access-from-files",
    "--remote-debugging-port=" + port,
    "--user-data-dir=" + dir,
    "about:blank",
  // detached, so the browser is a process-group leader: chromium forks a
  // zygote and a renderer per target, and killing only the process we spawned
  // leaves those behind holding the profile directory -- they do not die with
  // their parent, and the next run competes with them for the CPU.
  ], { stdio: ["ignore", "ignore", "pipe"], detached: true });

  let stderr = "";
  proc.stderr.on("data", d => { stderr += d.toString(); });

  const base = "http://127.0.0.1:" + port;
  for (let i = 0; i < 200; i++){
    try {
      const r = await fetch(base + "/json/version");
      if (r.ok) break;
    } catch {}
    if (i === 199) throw new Error("chromium never came up:\n" + stderr.slice(-2000));
    await sleep(100);
  }
  // A page target to drive. /json/list gives one per tab, already open.
  let target = null;
  for (let i = 0; i < 100 && !target; i++){
    const list = await (await fetch(base + "/json/list")).json();
    target = list.find(t => t.type === "page");
    if (!target) await sleep(100);
  }
  if (!target) throw new Error("no page target");
  return { proc, ws: await connect(target.webSocketDebuggerUrl), dir,
           close: async () => {
             try { process.kill(-proc.pid, "SIGKILL"); }
             catch { try { proc.kill("SIGKILL"); } catch {} }
             // Chromium keeps writing cache files for a moment after the kill,
             // so a single rm can lose the race and leave the temp dir behind.
             for (let i = 0; i < 5; i++){
               try { await rm(dir, { recursive: true, force: true }); return; }
               catch { await sleep(200); }
             }
           } };
}
async function mkdtemp(){
  const d = path.join(os.tmpdir(), "oled-bake-" + Math.random().toString(36).slice(2));
  await mkdir(d, { recursive: true });
  return d;
}

// A CDP connection: one socket, a promise per message id. Node has WebSocket
// built in, so this needs no dependency.
function connect(url){
  return new Promise((res, rej) => {
    const ws = new WebSocket(url);
    const waiting = new Map();
    let id = 0, events = [];
    const api = {
      send(method, params = {}){
        return new Promise((ok, no) => {
          const m = ++id;
          waiting.set(m, { ok, no });
          ws.send(JSON.stringify({ id: m, method, params }));
        });
      },
      on(fn){ events.push(fn); },
      close(){ try { ws.close(); } catch {} },
    };
    ws.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.id && waiting.has(msg.id)){
        const { ok, no } = waiting.get(msg.id);
        waiting.delete(msg.id);
        msg.error ? no(new Error(msg.method + ": " + JSON.stringify(msg.error))) : ok(msg.result);
      } else if (msg.method) for (const fn of events) fn(msg);
    };
    ws.onerror = e => rej(new Error("ws error: " + e.message));
    ws.onopen = () => res(api);
  });
}

async function openPage(port, url){
  const done = new Promise(res => port.on(m => { if (m.method === "Page.loadEventFired") res(true); }));
  await port.send("Page.enable");
  await port.send("Runtime.enable");
  await port.send("Page.navigate", { url });
  await Promise.race([done, sleep(60000)]);
  // Poll for the page to have compiled the shader rather than trusting the
  // load event: load fires before a big shader has had its first draw.
  for (let i = 0; i < 600; i++){
    const r = await evaluate(port, "typeof window.__meta === 'function' ? JSON.stringify(window.__meta()) : ''");
    if (r && r.includes('"ready":true')){
      const meta = JSON.parse(r);
      if (meta.error) throw new Error("page reports: " + meta.error);
      return meta;
    }
    if (r && r.includes('"error"') && !r.includes('"error":""')){
      const meta = JSON.parse(r);
      if (meta.error) throw new Error("shader: " + meta.error);
    }
    await sleep(100);
  }
  throw new Error("page never became ready");
}

async function evaluate(port, expr, awaitPromise = false){
  const r = await port.send("Runtime.evaluate", {
    expression: expr, returnByValue: true, awaitPromise,
  });
  if (r.exceptionDetails){
    const d = r.exceptionDetails;
    throw new Error("page exception: " + (d.exception && (d.exception.description || d.exception.value) || d.text));
  }
  return r.result && r.result.value;
}

// ------------------------------------------------------------------- renders
// The URL the page is opened with decides the *live* defaults; a bake overrides
// every one of them per call, so one browser can render the whole pool.
function renderExpr(o){
  return `JSON.stringify(window.__render(${JSON.stringify(o)}))`;
}
async function render(port, o){
  const raw = await evaluate(port, renderExpr(o));
  const r = JSON.parse(raw);
  if (r.error) throw new Error("render: " + r.error);
  return r;
}

function decode(dataUrl){
  const i = dataUrl.indexOf(",");
  return Buffer.from(dataUrl.slice(i + 1), "base64");
}

// ---------------------------------------------------------------------- pool
// The rotation is the burn-in fix, so the order matters as much as the frames:
// two neighbours never share a scene or a palette, which is what stops the
// same regions of the panel from being the bright ones every time.
function schedule(count){
  const out = [];
  let pi = 0;
  for (let i = 0; i < count; i++){
    const mode = i % MODES.length;
    // Step the palette by a stride coprime with its length so a scene and a
    // palette only line up again after a full lap.
    pi = (pi + 5) % PALETTES.length;
    const palette = PALETTES[pi];
    const seed = 1 + i*7.31;
    // A different moment in the animation for every still. The whisper scene
    // ignores most of it, so give it its own cheap variation.
    const t = 6.0 + i*3.7;
    const quiet = (i % 5 === 4);            // every fifth still runs dim
    out.push({ mode, modeName: MODES[mode], palette, seed, t,
               peak: quiet ? PEAK*0.62 : PEAK, quiet });
  }
  return out;
}

async function bakePool(){
  await mkdir(OUT, { recursive: true });
  // Anything left from an earlier run would be orphaned in the manifest.
  for (const f of await readdir(OUT).catch(() => []))
    if (f.endsWith(".webp") || f.endsWith(".png")) await rm(path.join(OUT, f));

  const jobs = schedule(COUNT);
  const manifest = [];
  let done = 0;

  const tty = process.stdout.isTTY;
  const line = () => {
    const pct = Math.round(100*done/COUNT);
    const s = `baking ${done}/${COUNT} ${String(pct).padStart(3)}%`;
    process.stdout.write((tty ? "\r" + s.padEnd(40) : s + "\n"));
  };

  const queue = jobs.map((job, i) => ({ job, i }));
  const workers = Array.from({ length: Math.min(JOBS, queue.length) }, async () => {
    const chrome = await launch();
    await openPage(chrome.ws, "file://" + LIVE + "?preserve=1&dpr=1");
    try {
      for (;;){
        const item = queue.shift();
        if (!item) break;
        const { job, i } = item;
        const name = `${String(i).padStart(2, "0")}-${job.modeName}-${job.palette}${job.quiet ? "-quiet" : ""}.${EXT}`;
        // Sample the scene, look at what came out, and move on if it is an
        // outlier. Both the moment *and* the noise realisation are moved: a
        // sparse seed of the nebula field stays sparse at every moment, so a
        // sampler that only advances time cannot rescue it.
        //
        // Scored rather than accepted-or-rejected, because the failure modes
        // are not symmetric. Too bright is a burn-in problem and has a budget;
        // too dark is a "that is not a wallpaper" problem with no budget at
        // all, and when neither can be satisfied the legible frame is the one
        // worth keeping.
        const score = (s, whisper) => {
          const lit = whisper ? s.over25 >= 0.008 : s.over25 >= 0.020;
          const reads = s.max >= 0.40 && lit;
          if (reads && s.apl <= APL_MAX) return 3;      // in budget
          if (reads) return 2;                          // legible, too much light
          if (s.apl <= APL_MAX) return 1;               // dark, and blank
          return 0;
        };
        const better = (cand, best) => {
          const a = score(cand.stats, job.modeName === "whisper");
          const b = score(best.stats, job.modeName === "whisper");
          if (a !== b) return a > b;
          // Within "dark and blank", more of the frame lit is the better frame;
          // everywhere else the least light is.
          return a === 1 ? cand.stats.over25 > best.stats.over25
                         : cand.stats.apl < best.stats.apl;
        };
        let r = null;
        for (let attempt = 0; attempt < 5; attempt++){
          const cand = await render(chrome.ws, {
            w: W, h: H, mode: job.mode,
            seed: job.seed + attempt*3.7,
            t: job.t + attempt*2.9,
            palette: job.palette, peak: job.peak, oct: OCT, dither: DITHER,
            ditherMode: DITHER_MODE, format: MIME, quality: QUALITY, hue: 0, zoom: 1, mix: 0,
          });
          if (!r || better(cand, r)) r = cand;
          if (score(cand.stats, job.modeName === "whisper") === 3) break;
        }
        job.seed = r.seed; job.t = r.t;
        const buf = decode(r.dataUrl);
        await writeFile(path.join(OUT, name), buf);
        manifest[i] = { file: name, bytes: buf.length, mode: job.mode,
                        modeName: job.modeName, palette: job.palette, seed: job.seed,
                        t: job.t, peak: job.peak, dither: DITHER, ditherMode: DITHER_MODE,
                        quiet: !!job.quiet, baked: r.stats };
        done++; line();
      }
    } finally { await chrome.close(); }
  });
  await Promise.all(workers);
  if (tty) process.stdout.write("\n");

  const ok = manifest.filter(Boolean);
  await writeFile(path.join(OUT, "manifest.json"), JSON.stringify({
    generated: new Date().toISOString(), width: W, height: H, format: FORMAT,
    quality: QUALITY, oct: OCT, dither: DITHER,
    note: "made by bake.mjs from live.html",
    frames: ok,
  }, null, 1) + "\n");
  await writePreview(OUT, ok);
  report("pool", ok.map(m => ({ ...m.baked, name: m.file, modeName: m.modeName })));
  console.log(`\n${ok.length} frames -> ${OUT}/  (${(ok.reduce((a, m) => a + m.bytes, 0)/1e6).toFixed(1)} MB, ${((Date.now() - STARTED)/1000).toFixed(0)}s)`);
  if (W !== 5120 || H !== 1440)
    console.log(`note: baked at ${W}x${H}; for this desk the joined layout is 5120x1440`);
  return ok;
}

// --------------------------------------------------------------------- verify
// Measures the files that are on disk, through the same decoder the shell will
// use. A bake that silently produced a grey frame, the wrong size, or a colour
// profile shifted by a revision is caught here and not on the desk.
async function verify(){
  const names = (await readdir(DIR)).filter(f => f.endsWith(".webp") || f.endsWith(".png")).sort();
  if (!names.length) throw new Error("nothing to verify in " + DIR);
  const chrome = await launch();
  try {
    await openPage(chrome.ws, "file://" + LIVE + "?preserve=1");
    const wantDiff = !!flag("diff", false);
    const items = names.map(n => ({ name: n, url: "file://" + path.resolve(DIR, n),
                                    params: null }));
    // The manifest carries what made each file, so the same parameters can be
    // re-rendered and differenced against the bytes that were written.
    let mf = { frames: [] };
    try { mf = JSON.parse(await readFile(path.join(DIR, "manifest.json"), "utf8")); } catch {}
    const pmap = Object.fromEntries((mf.frames || []).map(f => [f.file, f]));
    for (const it of items){
      const m = pmap[it.name];
      if (m) it.params = { w: mf.width, h: mf.height, mode: m.mode, seed: m.seed, t: m.t,
                           palette: m.palette, peak: m.peak, oct: mf.oct,
                           dither: m.dither === undefined ? 1 : m.dither,
                           ditherMode: m.ditherMode === undefined ? 0 : m.ditherMode,
                           hue: 0, zoom: 1, mix: 0 };
    }
    const out = [];
    for (let i = 0; i < items.length; i += 8)
      out.push(...await evaluate(chrome.ws,
        `window.__verify(${JSON.stringify(items.slice(i, i+8))}, ${JSON.stringify({ diff: wantDiff })})`, true));
    let manifest = { frames: [] };
    try { manifest = JSON.parse(await readFile(path.join(DIR, "manifest.json"), "utf8")); } catch {}
    const byName = Object.fromEntries((manifest.frames || []).map(f => [f.file, f]));
    const bad = [];
    const rows = out.map(r => {
      const m = byName[r.name] || {};
      const e = { ...r, modeName: m.modeName, peak: m.peak, url: undefined };
      if (r.error) bad.push(`${r.name}: ${r.error}`);
      else {
        if (r.w !== (manifest.width || r.w) || r.h !== (manifest.height || r.h))
          bad.push(`${r.name}: ${r.w}x${r.h} != ${manifest.width}x${manifest.height}`);
        // The budget. `apl` is the mean light emitted and `drive50` is how
        // much of the panel runs hard — those two are the burn-in half. `max`
        // is whether the frame reads at all, and a large `over25` is a flat
        // wash, which lights the whole panel and is the worst shape for OLED.
        if (r.apl > 0.080) bad.push(`${r.name}: mean drive ${(r.apl*100).toFixed(1)}% is too much light`);
        if (r.drive50 > 0.008) bad.push(`${r.name}: ${(r.drive50*100).toFixed(2)}% of pixels over half drive`);
        if (r.over25 > 0.62) bad.push(`${r.name}: ${(r.over25*100).toFixed(0)}% of pixels over 25% grey — a wash, not a picture`);
        if (r.max < 0.40) bad.push(`${r.name}: brightest pixel only ${r.max.toFixed(2)} — reads as blank`);
        if (r.max > 0.95) bad.push(`${r.name}: brightest pixel ${r.max.toFixed(2)} — near white`);
        // 6/255 of error at most, in an image whose whole point is that its
        // dark end is smooth. More than this and the encoder has banded it.
        if (r.maxDiff !== undefined && r.maxDiff > 6/255)
          bad.push(`${r.name}: ${(r.maxDiff*255).toFixed(0)}/255 from the render — the encode is lossy enough to band`);
        if (r.over2 !== undefined && r.over2 > 0.02)
          bad.push(`${r.name}: ${(r.over2*100).toFixed(1)}% of channels off by more than 2/255`);
      }
      return e;
    });
    report("files on disk", rows);
    if (bad.length){ console.log("\nFAILED:\n  " + bad.join("\n  ")); process.exitCode = 1; }
    else console.log(`\n${rows.length} files pass: right size, dark, and not blank.`);
  } finally { await chrome.close(); }
}

function report(title, rows){
  const cols = ["name","modeName","apl","aplS","max","over25","drive50","maxDiff"];
  const p = v => v === undefined ? "-" : (v*100).toFixed(2) + "%";
  const f = { name: 30, modeName: 9, apl: 8, aplS: 8, max: 7, over25: 9, drive50: 9, maxDiff: 9 };
  const cell = (r, c) => {
    const v = r[c];
    if (v === undefined) return "-";
    if (c === "max" || c === "maxDiff") return v.toFixed(3);
    if (c === "name" || c === "modeName") return String(v);
    return p(v);
  };
  console.log(`\n${title}\n`);
  console.log(cols.map(c => c.padEnd(f[c])).join(""));
  console.log(cols.map(c => "-".repeat(f[c])).join(""));
  for (const r of rows)
    console.log(cols.map(c => cell(r, c).padEnd(f[c])).join(""));
  console.log("\napl/aplS = mean over the frame (linear drive / displayed value); drive50 = fraction over half drive.");
}

// ---------------------------------------------------------------------- sheet
// A preview.html over the real files, so what is judged is the artifact. The
// png rendition of it is for reading in a terminal-less place.
async function writePreview(dir, frames){
  if (!frames.length) return;
  const rows = frames.map(f => `
    <figure>
      <img src="${encodeURIComponent(f.file)}" alt="${f.file}" loading="lazy">
      <figcaption><b>${String(f.mode).padStart(2,"0")} ${f.modeName}</b> · ${f.palette}${f.quiet ? " · quiet" : ""}
        <span>${(f.baked.apl*100).toFixed(2)}% drive · ${(f.baked.max).toFixed(2)} peak</span></figcaption>
    </figure>`).join("");
  const html = `<!doctype html><meta charset="utf-8"><title>oled pool</title>
<style>
 :root{color-scheme:dark}
 body{margin:0;background:#0a0a0b;color:#c5c9c5;
      font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;padding:1.6rem 1.6rem 3rem}
 h1{font-size:1rem;font-weight:600;color:#c4b28a;margin:0 0 .3rem}
 p{margin:0 0 1.4rem;color:#7d8280;max-width:70ch}
 .grid{display:grid;gap:1.1rem;grid-template-columns:repeat(auto-fill,minmax(30rem,1fr))}
 figure{margin:0;background:#111;border:1px solid #1e1e20;border-radius:10px;overflow:hidden}
 img{display:block;width:100%;height:auto;background:#000;aspect-ratio:32/9;object-fit:cover}
 figcaption{padding:.55rem .7rem;display:flex;justify-content:space-between;gap:1rem;align-items:baseline}
 figcaption b{color:#8ea4a2;font-weight:600}
 figcaption span{color:#6f7472;font-size:11px;white-space:nowrap}
</style>
<h1>oled wallpaper pool — ${frames.length} frames, ${frames[0].baked.w}x${frames[0].baked.h}</h1>
<p>The order below is the rotation order: no two neighbours share a scene or a
palette. The number to watch is <b>drive</b>: the mean light emitted, which is what ages a
subpixel. A <i>peak</i> near 1.0, or a large area over 25% grey, is a frame that
lights the whole panel — the shape an OLED dislikes most.</p>
<div class="grid">${rows}</div>`;
  await writeFile(path.join(dir, "preview.html"), html);
}

async function sheet(){
  const out = OUT.endsWith(".png") ? OUT : "preview.png";
  const prev = path.resolve(DIR, "preview.html");
  if (!existsSync(prev)) throw new Error("run `bake.mjs pool` first (no " + prev + ")");
  const chrome = await launch();
  try {
    const port = chrome.ws;
    await port.send("Page.enable");
    await port.send("Emulation.setDeviceMetricsOverride",
      { width: 1200, height: 900, deviceScaleFactor: 1, mobile: false });
    await port.send("Page.navigate", { url: "file://" + prev });
    await sleep(2500);
    const { data } = await port.send("Page.captureScreenshot",
      { format: "png", captureBeyondViewport: true });
    await writeFile(out, Buffer.from(data, "base64"));
    console.log("wrote " + out);
  } finally { await chrome.close(); }
}

// ------------------------------------------------------------------- selftest
// Every scene, small, with the exposure numbers: this is what says a scene is
// dark enough to ship without anyone having to look at a contact sheet first.
async function selftest(){
  const chrome = await launch();
  try {
    await openPage(chrome.ws, "file://" + LIVE + "?preserve=1");
    const rows = [];
    for (let m = 0; m < MODES.length; m++){
      for (const palette of ["dragon", "synthwave"]){
        const r = await render(chrome.ws, {
          w: W, h: H, mode: m, seed: 3.5 + m, t: 11.25, palette, peak: PEAK,
          oct: OCT, dither: 1, format: MIME, quality: QUALITY,
        });
        rows.push({ ...r.stats, name: MODES[m] + " / " + palette, modeName: MODES[m] });
      }
    }
    report("all scenes", rows);

    // The dissolve is a mix *towards* u_mode2, so a weight of 1 has to be
    // exactly the second scene and a weight of 0 exactly the first. That is the
    // invariant the player leans on when it hands over 1-progress instead of
    // progress, and a blend wired the other way round is invisible to every
    // average in the table above -- it just quietly puts the old scene back.
    const base = { w: 320, h: 90, oct: OCT, palette: "dragon", peak: PEAK, t: 5, seed: 2, dither: DITHER };
    const first  = await render(chrome.ws, { ...base, mode: 0, mix: 0 });
    const second = await render(chrome.ws, { ...base, mode: 4, mix: 0 });
    const atOne  = await render(chrome.ws, { ...base, mode: 0, mode2: 4, mix: 1 });
    const atZero = await render(chrome.ws, { ...base, mode: 0, mode2: 4, mix: 0 });
    const okOne  = atOne.dataUrl === second.dataUrl;
    const okZero = atZero.dataUrl === first.dataUrl;
    console.log(`\ndissolve: mix=1 is scene 2 exactly: ${okOne ? "yes" : "NO"}` +
                `   mix=0 is scene 1 exactly: ${okZero ? "yes" : "NO"}`);
    if (!okOne || !okZero) process.exitCode = 1;
    const bad = [];
    for (const r of rows){
      if (r.apl > 0.080) bad.push(`${r.name}: mean drive ${(r.apl*100).toFixed(1)}%`);
      if (r.max < 0.40) bad.push(`${r.name}: max ${r.max.toFixed(2)} too dim`);
      if (r.drive50 > 0.008) bad.push(`${r.name}: ${(r.drive50*100).toFixed(2)}% over half drive`);
    }
    console.log(bad.length ? "\nover budget:\n  " + bad.join("\n  ") : "\nall scenes within the drive budget.");
  } finally { await chrome.close(); }
}

// ----------------------------------------------------------------------- main
const run = { selftest, pool: bakePool, verify, sheet }[cmd];
if (!run){ console.error("usage: bake.mjs [selftest|pool|verify|sheet] [flags]"); process.exit(2); }
run().catch(e => { console.error("bake.mjs: " + e.message); process.exit(1); });
