#!/usr/bin/env node
// Checks a generated demo page in headless Chrome, for bin/wasm-bytes check ui.
//
//   node scripts/ui-check.mjs --chrome PATH --dir DIR
//
// DIR/real holds the page as index.html with the recorded modules in
// modules.js; DIR/probe holds the same page with stand-in modules that
// always return 250 (original) and -125 (reversed). Prints one JSON object:
// {"chrome": ..., "checks": [{"name", "ok", "detail"}]}.
//
// Before the page's own scripts run, the checker wraps the WebAssembly and
// Web Audio functions the page may use. It records every screen_pan call
// with the module that answered, and every sound the page starts, with the
// pan, pitch, loudness and length the page gave it. Clicks are real mouse
// events, so the browser applies its rules for starting audio.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const arg = (name) => {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const CHROME = arg("--chrome");
const DIR = arg("--dir");
const PHONE = { width: 390, height: 844 };

// Runs in the page before anything else.
const INSTRUMENT = `(() => {
  const log = { calls: [], beeps: [], session: [], media: [], instantiated: [], contexts: [] };
  Object.defineProperty(window, "__uiLog", { value: log });
  const now = () => performance.now();

  const b64 = (u8) => { let s = ""; for (let i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]); return btoa(s); };
  const bytesOf = (src) => src instanceof ArrayBuffer ? new Uint8Array(src)
    : ArrayBuffer.isView(src) ? new Uint8Array(src.buffer, src.byteOffset, src.byteLength) : null;
  const tagOf = (src) => {
    const u = bytesOf(src);
    if (!u) return "unknown";
    const text = b64(u), mods = window.PAN_MODULES || {};
    for (const k of Object.keys(mods)) if (mods[k] && mods[k].bytes === text) return k;
    return "unknown";
  };

  const W = WebAssembly;
  const OrigModule = W.Module, OrigInstance = W.Instance;
  const origInstantiate = W.instantiate, origCompile = W.compile;
  const moduleTags = new WeakMap();
  const wrapInstance = (inst, tag) => {
    log.instantiated.push(tag);
    const ex = inst.exports;
    if (!ex || typeof ex.screen_pan !== "function") return inst;
    const f = ex.screen_pan;
    const g = function (x) { const v = f.apply(this, arguments); log.calls.push({ t: now(), tag, x, v }); return v; };
    const copy = Object.freeze(Object.assign({}, ex, { screen_pan: g }));
    return Object.create(OrigInstance.prototype, { exports: { value: copy, enumerable: true } });
  };
  W.Module = function (src) { const m = new OrigModule(src); moduleTags.set(m, tagOf(src)); return m; };
  Object.assign(W.Module, { exports: OrigModule.exports, imports: OrigModule.imports, customSections: OrigModule.customSections });
  W.Module.prototype = OrigModule.prototype;
  W.Instance = function (m, imp) { return wrapInstance(new OrigInstance(m, imp), moduleTags.get(m) || "unknown"); };
  W.Instance.prototype = OrigInstance.prototype;
  W.compile = async function (src) { const m = await origCompile.call(W, src); moduleTags.set(m, tagOf(src)); return m; };
  W.instantiate = async function (src, imp) {
    const r = await origInstantiate.call(W, src, imp);
    if (r instanceof OrigInstance) return wrapInstance(r, moduleTags.get(src) || "unknown");
    return { module: r.module, instance: wrapInstance(r.instance, tagOf(src)) };
  };

  // Web Audio: the connections, the parameter values, and each sound started.
  const edges = new WeakMap(), events = new WeakMap();
  const record = (p, e) => { let a = events.get(p); if (!a) events.set(p, a = []); a.push(e); };
  const AP = window.AudioParam && AudioParam.prototype;
  if (AP) {
    for (const m of ["setValueAtTime", "linearRampToValueAtTime", "exponentialRampToValueAtTime", "setTargetAtTime"]) {
      const f = AP[m];
      AP[m] = function (v, t) { record(this, { m, v, t }); return f.apply(this, arguments); };
    }
    const curve = AP.setValueCurveAtTime;
    if (curve) AP.setValueCurveAtTime = function (vals, t) { record(this, { m: "curve", v: Math.max(...vals), t }); return curve.apply(this, arguments); };
    const d = Object.getOwnPropertyDescriptor(AP, "value");
    Object.defineProperty(AP, "value", { configurable: true, enumerable: d.enumerable,
      get() { return d.get.call(this); },
      set(v) { record(this, { m: "value", v, t: -1 }); d.set.call(this, v); } });
  }
  const valueAt = (p, when) => {
    let v = null;
    for (const e of events.get(p) || []) if (e.m === "value" || e.t <= when + 1e-6) v = e.v;
    return v === null ? p.value : v;
  };
  // The loudest value scheduled on a gain; its current value only when nothing
  // was scheduled, since before the first event it still reads its default.
  const peakOf = (p) => { const e = events.get(p) || []; return e.length ? Math.max(...e.map((x) => x.v)) : p.value; };
  const AN = window.AudioNode && AudioNode.prototype;
  if (AN) {
    const connect = AN.connect;
    AN.connect = function (dest) {
      if (dest instanceof AudioNode) { let s = edges.get(this); if (!s) edges.set(this, s = new Set()); s.add(dest); }
      return connect.apply(this, arguments);
    };
  }
  const ASN = window.AudioScheduledSourceNode && AudioScheduledSourceNode.prototype;
  if (ASN) {
    const start = ASN.start, stop = ASN.stop;
    // A beep is measured as the page scheduled it: start(0) means time 0 on
    // the page's clock even if the audio clock has moved on, so the length
    // is stop minus start as the page wrote them.
    ASN.start = function (when) {
      const at = when === undefined ? this.context.currentTime : when;
      const seen = new Set(), queue = [this];
      let panner = null, reaches = false, loud = 1;
      while (queue.length) {
        const n = queue.shift();
        if (seen.has(n)) continue;
        seen.add(n);
        if (n instanceof AudioDestinationNode) reaches = true;
        if (!panner && window.StereoPannerNode && n instanceof StereoPannerNode) panner = n;
        if (n instanceof GainNode) loud *= peakOf(n.gain);
        for (const d of edges.get(n) || []) queue.push(d);
      }
      const beep = { t: now(), at, kind: this.constructor.name, reaches,
        pan: panner ? valueAt(panner.pan, at) : null,
        frequency: this.frequency ? valueAt(this.frequency, at) : null,
        type: this.type || null, loud, buffer: this.buffer ? this.buffer.duration : null, stop: null };
      this.__beep = beep;
      log.beeps.push(beep);
      return start.apply(this, arguments);
    };
    ASN.stop = function (when) {
      if (this.__beep) this.__beep.stop = when === undefined ? this.context.currentTime : when;
      return stop.apply(this, arguments);
    };
  }
  const Ctx = window.AudioContext;
  if (Ctx) {
    const C = function (...a) { const c = new Ctx(...a); log.contexts.push(c); return c; };
    C.prototype = Ctx.prototype;
    window.AudioContext = C;
    window.webkitAudioContext = C;
  }

  // The audio session Safari 17 on iOS has, and media playback, the two ways
  // a page can keep the silent switch from muting it.
  let sessionType = "auto";
  try {
    Object.defineProperty(Navigator.prototype, "audioSession", { configurable: true,
      get() { return { get type() { return sessionType; }, set type(v) { sessionType = v; log.session.push({ t: now(), v }); } }; } });
  } catch (e) { /* not definable here */ }
  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () { log.media.push({ t: now() }); return play.apply(this, arguments); };
})();`;

const SNAPSHOT = `JSON.stringify({
  calls: __uiLog.calls, beeps: __uiLog.beeps, session: __uiLog.session, media: __uiLog.media,
  instantiated: __uiLog.instantiated, contexts: __uiLog.contexts.map((c) => c.state),
  reading: (document.getElementById("reading") || {}).textContent ?? null, now: performance.now() })`;

// The DevTools protocol over --remote-debugging-pipe: JSON messages ended by
// a zero byte, written to the browser's fd 3 and read from its fd 4.
function startChrome(profile) {
  const flags = ["--headless=new", "--remote-debugging-pipe", "--no-first-run", "--no-default-browser-check",
    "--disable-gpu", "--disable-dev-shm-usage", "--mute-audio", "--window-size=1200,900",
    `--user-data-dir=${profile}`];
  if (process.getuid && process.getuid() === 0) flags.push("--no-sandbox");
  const proc = spawn(CHROME, flags, { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"] });
  const pending = new Map(), listeners = [];
  let id = 0, buf = Buffer.alloc(0);
  proc.stdio[4].on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    let end;
    while ((end = buf.indexOf(0)) >= 0) {
      const msg = JSON.parse(buf.subarray(0, end).toString("utf8"));
      buf = buf.subarray(end + 1);
      if (msg.id && pending.has(msg.id)) {
        const p = pending.get(msg.id);
        pending.delete(msg.id);
        msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
      } else {
        for (const f of listeners) f(msg);
      }
    }
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const msg = { id: ++id, method, params };
    if (sessionId) msg.sessionId = sessionId;
    pending.set(msg.id, { resolve, reject });
    proc.stdio[3].write(JSON.stringify(msg) + "\0");
  });
  return { proc, send, on: (f) => listeners.push(f) };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const numbers = (text) => (String(text || "").replace(/−/g, "-").match(/-?\d+/g) || []).map(Number);
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : NaN; };

async function main() {
  const profile = mkdtempSync(join(tmpdir(), "wasm-bytes-ui-"));
  const chrome = startChrome(profile);
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok: Boolean(ok), detail: String(detail) });
  const exceptions = [], requests = [];
  try {
    const { product } = await chrome.send("Browser.getVersion");
    const { targetId } = await chrome.send("Target.createTarget", { url: "about:blank" });
    const { sessionId: sid } = await chrome.send("Target.attachToTarget", { targetId, flatten: true });
    const send = (m, p) => chrome.send(m, p, sid);
    chrome.on((msg) => {
      if (msg.sessionId !== sid) return;
      if (msg.method === "Runtime.exceptionThrown") {
        const d = msg.params.exceptionDetails;
        exceptions.push((d.exception && d.exception.description) || d.text);
      }
      if (msg.method === "Network.requestWillBeSent") requests.push(msg.params.request.url);
    });
    await send("Page.enable");
    await send("Runtime.enable");
    await send("Network.enable");
    await send("Page.addScriptToEvaluateOnNewDocument", { source: INSTRUMENT });
    const evaluate = async (expression) =>
      (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result.value;
    const snap = async () => JSON.parse(await evaluate(SNAPSHOT));
    // Clicks the element and returns the page's clock just after the click,
    // so that a check can time what follows from the click itself, however
    // long the browser took to deliver it; null if the element is missing.
    const click = async (id) => {
      const r = await evaluate(`(() => { const e = document.getElementById(${JSON.stringify(id)});
        if (!e) return null; e.scrollIntoView({ block: "center" });
        const b = e.getBoundingClientRect(); return { x: b.left + b.width / 2, y: b.top + b.height / 2, w: b.width }; })()`);
      if (!r || !r.w) return null;
      for (const type of ["mousePressed", "mouseReleased"]) {
        await send("Input.dispatchMouseEvent", { type, x: r.x, y: r.y, button: "left", clickCount: 1 });
      }
      return evaluate("performance.now()");
    };
    const open = async (sub) => {
      await send("Page.navigate", { url: pathToFileURL(join(DIR, sub, "index.html")).href });
      await sleep(1500);
    };

    // The recorded modules, run here too, for the values the page should show.
    const mods = JSON.parse(readFileSync(join(DIR, "real", "modules.js"), "utf8").replace(/^[^{]*/, "").replace(/;\s*$/, ""));
    const fn = async (k) => (await WebAssembly.instantiate(Buffer.from(mods[k].bytes, "base64"))).instance.exports.screen_pan;
    const expected = { original: await fn("original"), reversed: await fn("reversed") };

    const panned = (beeps, after) => beeps.filter((b) => b.t > after && b.reaches && b.pan !== null);
    const panMatches = (s, beeps, tag, value) => {
      for (const b of beeps) {
        const wanted = value !== undefined ? [value]
          : s.calls.filter((c) => c.tag === tag && c.t <= b.t + 1 && c.t >= b.t - 120).map((c) => c.v);
        if (!wanted.some((v) => Math.abs(b.pan - v / 500) < 1e-3)) {
          return `a beep at ${Math.round(b.t)} ms has pan ${b.pan}; the ${tag} module returned ${wanted.slice(-3).join(", ") || "nothing just before it"}`;
        }
      }
      return null;
    };
    const showsCall = (s, tag, since) => {
      const recent = s.calls.filter((c) => c.tag === tag && c.t >= since).slice(-12);
      const shown = numbers(s.reading);
      return recent.some((c) => shown.includes(c.x) && shown.includes(c.v));
    };

    // The recorded modules.
    exceptions.length = 0;
    await open("real");
    let s = await snap();
    check("loads", exceptions.length === 0 && s.instantiated.includes("original") && s.instantiated.includes("reversed"),
      exceptions.length ? `uncaught error: ${exceptions[0]}`
        : `modules instantiated: ${s.instantiated.join(", ") || "none"}`);
    const xs = s.calls.filter((c) => c.t > s.now - 1000).map((c) => c.x);
    check("animates", new Set(xs).size >= 5 && xs.every((x) => Number.isInteger(x) && x >= 0 && x <= 640),
      `${new Set(xs).size} different positions passed to screen_pan in one second, from ${Math.min(...xs)} to ${Math.max(...xs)}`);
    check("reading", s.reading !== null && (showsCall(s, "original", s.now - 400) || showsCall(s, "reversed", s.now - 400)),
      s.reading === null ? "no element with id reading" : `reading shows "${s.reading.trim().replace(/\s+/g, " ")}"`);

    await click("mode-original");
    await sleep(600);
    let t = (await snap()).now;
    await click("sound");
    await sleep(1300);
    s = await snap();
    const onBeeps = panned(s.beeps, t);
    const gaps = onBeeps.slice(1).map((b, i) => b.t - onBeeps[i].t);
    check("sound_on", s.contexts.includes("running") && onBeeps.length >= 3 && median(gaps) >= 150 && median(gaps) <= 260,
      `after one click: audio ${s.contexts.join("/") || "never created"}, ${onBeeps.length} panned beeps in 1.3 s, ${Math.round(median(gaps))} ms apart`);
    check("ios_audio", s.session.some((e) => e.v === "playback" && e.t >= t - 50) || s.media.some((e) => e.t >= t - 50),
      s.session.length ? `audio session set to ${s.session.map((e) => e.v).join(", ")}`
        : s.media.length ? "a media element played" : "no media playback requested when the sound turned on");
    const panOriginal = onBeeps.length ? panMatches(s, onBeeps, "original") : "no beeps";

    t = (await click("mode-reversed")) ?? s.now;
    await sleep(1300);
    s = await snap();
    const afterSwitch = s.calls.filter((c) => c.t > t + 150);
    const toReversed = afterSwitch.length > 0 && afterSwitch.every((c) => c.tag === "reversed");
    const revBeeps = panned(s.beeps, t + 150);
    const panReversed = revBeeps.length ? panMatches(s, revBeeps, "reversed") : "no beeps";
    check("pan", !panOriginal && !panReversed, panOriginal || panReversed || `${onBeeps.length + revBeeps.length} beeps, each panned by the selected module's value / 500`);
    const signature = (b) => JSON.stringify([b.kind, b.type, b.frequency && b.frequency.toFixed(2), b.loud.toFixed(4),
      b.stop === null ? null : (b.stop - b.at).toFixed(3), b.buffer]);
    const sigOn = new Set(onBeeps.map(signature)), sigRev = new Set(revBeeps.map(signature));
    check("same_beep", sigOn.size > 0 && sigOn.size === sigRev.size && [...sigOn].every((x) => sigRev.has(x)),
      `original beeps ${[...sigOn].join(" ")}; reversed beeps ${[...sigRev].join(" ")}`);

    t = (await click("pause")) ?? s.now;
    await sleep(500);
    s = await snap();
    const heldXs = new Set(s.calls.filter((c) => c.t > t + 200).map((c) => c.x));
    const shown = numbers(s.reading);
    const heldX = heldXs.size === 1 ? [...heldXs][0] : shown.find((n) => n >= 0 && n <= 640);
    await click("mode-original");
    await sleep(500);
    s = await snap();
    const shownAfter = numbers(s.reading);
    const wantedOriginal = expected.original(heldX);
    const pauseHolds = heldXs.size <= 1;
    const pauseUpdates = shownAfter.includes(heldX) && shownAfter.includes(wantedOriginal);
    t = (await click("pause")) ?? s.now;
    await sleep(800);
    s = await snap();
    const resumed = new Set(s.calls.filter((c) => c.t > t + 100).map((c) => c.x)).size >= 3;
    check("switch", toReversed && pauseUpdates,
      !toReversed ? `after selecting Reversed, screen_pan was called on ${[...new Set(afterSwitch.map((c) => c.tag))].join(", ") || "nothing"}`
        : !pauseUpdates ? `paused at x = ${heldX}, selecting Original shows "${(s.reading || "").trim().replace(/\s+/g, " ")}", not ${wantedOriginal}`
          : "each button selects the module screen_pan is called on");
    check("pause", pauseHolds && resumed, `${pauseHolds ? "holds one position" : `${heldXs.size} positions`} while paused; ${resumed ? "moves again" : "does not move again"} after the second click`);

    t = (await click("sound")) ?? s.now;
    await sleep(700);
    s = await snap();
    const lateBeeps = s.beeps.filter((b) => b.t > t + 100);
    check("sound_off", lateBeeps.length === 0, `${lateBeeps.length} sounds started after the second click`);

    // Stand-in modules: a page that computes the pan itself shows the wrong numbers.
    await open("probe");
    await click("mode-original");
    await sleep(500);
    await click("sound");
    await sleep(1000);
    s = await snap();
    const probeOriginal = numbers(s.reading).includes(250) && !panMatches(s, panned(s.beeps, s.now - 900), "original", 250)
      && panned(s.beeps, s.now - 900).length > 0;
    t = (await click("mode-reversed")) ?? s.now;
    await sleep(1000);
    s = await snap();
    const probeReversed = numbers(s.reading).includes(-125) && !panMatches(s, panned(s.beeps, t + 150), "reversed", -125)
      && panned(s.beeps, t + 150).length > 0;
    check("uses_module", probeOriginal && probeReversed,
      `with stand-in modules returning 250 and -125: original ${probeOriginal ? "shown and played" : "not shown or not played"}, reversed ${probeReversed ? "shown and played" : "not shown or not played"}`);

    const allowed = (u) => u.startsWith("file:") || u.startsWith("data:") || u.startsWith("blob:") || u.startsWith("about:");
    const outside = requests.filter((u) => !allowed(u));
    check("network", outside.length === 0, outside.length ? `requested ${outside[0]}` : "only the page and modules.js");

    // A phone-sized screen.
    await send("Emulation.setDeviceMetricsOverride", { width: PHONE.width, height: PHONE.height, deviceScaleFactor: 3, mobile: true });
    await open("real");
    const fit = await evaluate(`(() => {
      const wide = document.documentElement.scrollWidth;
      const out = ["sound", "mode-original", "mode-reversed", "pause", "reading"].filter((id) => {
        const e = document.getElementById(id); if (!e) return true;
        const b = e.getBoundingClientRect(); return !(b.width > 0 && b.left >= -1 && b.right <= ${PHONE.width + 1});
      });
      return { wide, out };
    })()`);
    check("phone", fit.wide <= PHONE.width + 1 && fit.out.length === 0,
      `page width ${fit.wide} px on a ${PHONE.width} px screen${fit.out.length ? `; outside the screen: ${fit.out.join(", ")}` : ""}`);

    process.stdout.write(JSON.stringify({ chrome: product, checks }) + "\n");
  } finally {
    chrome.proc.kill();
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* still in use */ }
  }
}

const timer = setTimeout(() => { process.stdout.write(JSON.stringify({ error: "timed out after 90 s" }) + "\n"); process.exit(2); }, 90_000);
main().then(() => { clearTimeout(timer); process.exit(0); },
  (e) => { process.stdout.write(JSON.stringify({ error: String(e && e.stack || e) }) + "\n"); process.exit(2); });
