#!/usr/bin/env node
// lib/capture.mjs — render one scene page to an mp4.
//
// The page is a pure function of the virtual clock (lib/clock.js), so one
// headless Chromium is loaded once and seeked to t = 0, 1000/fps, 2000/fps …
// Each frame is screenshotted and written straight into ffmpeg's stdin; no
// frame ever reaches the filesystem.
//
// Screenshots come back base64 inside a DevTools JSON message, so the format
// decides both how long Chromium spends encoding and how much JSON Node has to
// parse per frame. --format jpeg is several times cheaper than png on both
// counts; png --fast trades zlib compression level for speed and stays lossless.
//
// Usage: capture.mjs --page P --seconds S --out O [--fps 30] [--width 1920]
//                    [--height 1080] [--format jpeg|png] [--fast] [--crf 18]
//                    [--preset veryfast] [--quality 95] [--canvas-w 1920]
//                    [--canvas-h 1080]
import { spawn } from "node:child_process";
import { once } from "node:events";
import { resolve } from "node:path";

const args = new Map();
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (!a.startsWith("--")) continue;
  const k = a.slice(2);
  const next = process.argv[i + 1];
  if (next === undefined || next.startsWith("--")) args.set(k, "true");
  else { args.set(k, next); i++; }
}
const opt = (k, d) => args.get(k) ?? d;

const page = opt("page");
const out = opt("out");
const seconds = parseFloat(opt("seconds"));
const fps = parseInt(opt("fps", "30"), 10);
const W = parseInt(opt("width", "1920"), 10);
const H = parseInt(opt("height", "1080"), 10);
const format = opt("format", "jpeg");
const quality = parseInt(opt("quality", "95"), 10);
const fast = opt("fast", "false") !== "false";
const crf = opt("crf", "18");
const preset = opt("preset", "veryfast");
const theme = opt("theme", "light");
// Relative to the scene page, the way clock.js resolves it.
const css = opt("css", "");
// The canvas the scene pages lay themselves out on, which clock.js scales to
// WxH. Equal to the output size unless .meta.canvas says otherwise.
const AW = parseInt(opt("canvas-w", String(W)), 10);
const AH = parseInt(opt("canvas-h", String(H)), 10);

if (!page || !out || !(seconds > 0) || !(fps > 0) || !(W > 0) || !(H > 0)) {
  console.error("usage: capture.mjs --page P --seconds S --out O [--fps N] …");
  process.exit(2);
}
if (format !== "jpeg" && format !== "png") {
  console.error(`--format must be jpeg or png, got ${format}`);
  process.exit(2);
}
const total = Math.round(seconds * fps);
const pageUrl =
  `file://${resolve(page)}?fps=${fps}&w=${W}&h=${H}` +
  `&cw=${AW}&ch=${AH}&theme=${theme}` +
  (css ? `&css=${encodeURIComponent(css)}` : "") + "&t=";

// ---------------------------------------------------------------- chromium --
const profile = `/tmp/explainer-capture-${process.pid}`;
const chrome = spawn(process.env.CHROMIUM_BIN || "chromium", [
  "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
  `--window-size=${W},${H}`, "--force-device-scale-factor=1",
  "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  // Uncap the compositor: with vsync in play, the rAF below costs a 16ms
  // display frame per captured frame and dominates everything else.
  "--disable-frame-rate-limit", "--disable-gpu-vsync",
  "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] });

const ffmpeg = spawn("ffmpeg", [
  "-y", "-v", "error",
  "-f", "image2pipe", "-framerate", String(fps), "-i", "-",
  "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", crf, "-preset", preset,
  "-movflags", "+faststart", out,
], { stdio: ["pipe", "inherit", "inherit"] });

let shutdownOnce = null;
const shutdown = () => (shutdownOnce ??= (async () => {
  try { ffmpeg.stdin.destroy(); } catch { /* already gone */ }
  for (const p of [chrome, ffmpeg]) {
    if (p.exitCode === null && p.signalCode === null) p.kill("SIGKILL");
  }
})());
for (const sig of ["SIGINT", "SIGTERM"]) {
  process.once(sig, () => void shutdown().finally(() => process.exit(1)));
}

const wsUrl = await new Promise((res, rej) => {
  let buf = "";
  const timer = setTimeout(() => rej(new Error("timeout waiting for DevTools")), 30000);
  chrome.stderr.on("data", (d) => {
    buf += d;
    const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
    if (m) { clearTimeout(timer); res(m[1]); }
  });
  chrome.once("exit", (c) => { clearTimeout(timer); rej(new Error(`chromium exited (${c}): ${buf}`)); });
});

const ws = new WebSocket(wsUrl);
await once(ws, "open");

let seq = 0;
const pending = new Map();
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  const p = pending.get(msg.id);
  if (!p) return;
  pending.delete(msg.id);
  if (msg.error) p.rej(new Error(`${p.method}: ${JSON.stringify(msg.error)}`));
  else p.res(msg.result);
};
ws.onclose = () => {
  for (const p of pending.values()) p.rej(new Error("DevTools websocket closed"));
  pending.clear();
};
const send = (method, params = {}, sessionId) =>
  new Promise((res, rej) => {
    const id = ++seq;
    pending.set(id, { res, rej, method });
    ws.send(JSON.stringify({ id, method, params, sessionId }));
  });

const { targetId } = await send("Target.createTarget", { url: "about:blank" });
const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
await send("Page.enable", {}, sessionId);
await send("Runtime.enable", {}, sessionId);
await send("Emulation.setDeviceMetricsOverride",
  { width: W, height: H, deviceScaleFactor: 1, mobile: false }, sessionId);

// A thrown page exception comes back as exceptionDetails rather than a protocol
// error, so an exploded render() would otherwise be swallowed and every later
// frame captured from stale DOM — a silently wrong video.
async function evalJs(expression, awaitPromise = false) {
  const r = await send("Runtime.evaluate",
    { expression, awaitPromise, returnByValue: true }, sessionId);
  if (r.exceptionDetails) {
    const d = r.exceptionDetails;
    throw new Error(`page JS threw: ${d.exception?.description || d.text}`);
  }
  return r.result?.value;
}

// Fonts loaded and a frame elapsed, so layout is flushed before the capture,
// which composites a fresh frame of its own. A second rAF costs another display
// frame and changes no pixels.
const SETTLE =
  "document.fonts.ready.then(()=>new Promise(r=>requestAnimationFrame(r)))";

// -------------------------------------------------------------------- run --
const started = Date.now();
try {
  await send("Page.navigate", { url: pageUrl + "0" }, sessionId);
  await evalJs(SETTLE, true);
  if (await evalJs("typeof window.hfSeek==='function' && typeof window.render==='function'") !== true) {
    throw new Error(`${page} does not expose window.render — see lib/clock.js`);
  }

  const shot = { format, optimizeForSpeed: fast };
  if (format === "jpeg") shot.quality = quality;

  for (let i = 0; i < total; i++) {
    // One round trip, not two: at twenty-odd frames a second the protocol
    // latency of a second evaluate is no longer noise.
    await evalJs(`window.hfSeek(${Math.round((i * 1000) / fps)}); ${SETTLE}`, true);
    const { data } = await send("Page.captureScreenshot", shot, sessionId);
    if (!ffmpeg.stdin.write(Buffer.from(data, "base64"))) {
      await once(ffmpeg.stdin, "drain");
    }
    if (i === total - 1 || i % Math.max(1, Math.ceil(total / 5)) === 0) {
      const rate = (i + 1) / ((Date.now() - started) / 1000);
      process.stderr.write(`  ${i + 1}/${total} frames (${rate.toFixed(1)} fps)\n`);
    }
  }

  ffmpeg.stdin.end();
  const [code] = await once(ffmpeg, "exit");
  if (code !== 0) throw new Error(`ffmpeg exited ${code}`);
  const elapsed = (Date.now() - started) / 1000;
  console.log(
    `${out}: ${total} frames in ${elapsed.toFixed(1)}s ` +
    `(${(total / elapsed).toFixed(1)} fps, ${format}${fast ? "/fast" : ""})`
  );
} finally {
  await shutdown();
}
