// The demo host. It runs the two modules that bin/wasm-bytes pan-demo put
// in modules.js, and calls screen_pan(x) the same way whichever is selected.
"use strict";

const SWEEP_MS = 3200;      // left edge to right edge
const PAUSE_MS = 600;       // at the right edge, before the ball starts again
const BEEP_EVERY_MS = 200;  // one beep at the ball's position this often
const BEEP_HZ = 660;
const BEEP_GAIN = 0.18;
const BEEP_MS = 90;
const PAN_RANGE = 500;      // the recovered function's results run from -500 to 500

const $ = (id) => document.getElementById(id);
const clamp = (v) => Math.max(-1, Math.min(1, v));

// Sound, written for Safari on iOS as well as for desktop browsers.
// - The audio context is created and resumed inside the tap that turns sound
//   on, before anything is awaited: Safari only starts audio from a gesture.
// - iOS plays Web Audio on the ringer channel, which the silent switch mutes,
//   unless the page asks for media playback: through navigator.audioSession
//   where Safari has it, otherwise by playing a silent <audio> element.
// - A context interrupted by a call or by leaving the page resumes on the
//   next tap.
const AudioCtx = window.AudioContext || window.webkitAudioContext;

function silentWavUrl() {
  const samples = 2000;                       // a quarter second at 8 kHz
  const buf = new ArrayBuffer(44 + samples);
  const v = new DataView(buf);
  const text = (at, s) => { for (let i = 0; i < s.length; i++) v.setUint8(at + i, s.charCodeAt(i)); };
  text(0, "RIFF"); v.setUint32(4, 36 + samples, true); text(8, "WAVE"); text(12, "fmt ");
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
  v.setUint32(24, 8000, true); v.setUint32(28, 8000, true);
  v.setUint16(32, 1, true); v.setUint16(34, 8, true);
  text(36, "data"); v.setUint32(40, samples, true);
  for (let i = 0; i < samples; i++) v.setUint8(44 + i, 128);   // 8-bit silence
  return URL.createObjectURL(new Blob([buf], { type: "audio/wav" }));
}

const sound = {
  ctx: null,
  on: false,
  keepAlive: null,

  // Called from the tap itself, so nothing here may wait.
  set(on) {
    if (on) {
      this.mediaPlayback();
      if (!this.ctx) this.ctx = new AudioCtx();
      this.resume();
    } else {
      if (this.ctx) this.ctx.suspend();
      if (this.keepAlive) this.keepAlive.pause();
    }
    this.on = on;
  },

  mediaPlayback() {
    try {
      if (navigator.audioSession) {
        navigator.audioSession.type = "playback";
        return;
      }
    } catch (e) { /* fall back to the media element */ }
    if (!this.keepAlive) {
      this.keepAlive = new Audio(silentWavUrl());
      this.keepAlive.loop = true;
      this.keepAlive.setAttribute("playsinline", "");
    }
    const played = this.keepAlive.play();
    if (played && played.catch) played.catch(() => {});
  },

  resume() {
    if (!this.ctx) return;
    const resumed = this.ctx.resume();
    if (resumed && resumed.catch) resumed.catch(() => {});
    if (this.keepAlive && this.keepAlive.paused) {
      const played = this.keepAlive.play();
      if (played && played.catch) played.catch(() => {});
    }
  },

  running() {
    return this.on && this.ctx !== null && this.ctx.state === "running";
  },

  // The same beep in both modes; only the pan differs, and only because a
  // different module returned it. Built with the factory methods, which older
  // Safari has, with an equal-power panner where StereoPannerNode is missing.
  beep(pan) {
    if (!this.running()) return;
    const ctx = this.ctx;
    const t = ctx.currentTime;
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.value = BEEP_HZ;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(BEEP_GAIN, t + 0.005);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + BEEP_MS / 1000);
    let panner;
    if (ctx.createStereoPanner) {
      panner = ctx.createStereoPanner();
      panner.pan.value = pan;
    } else {
      panner = ctx.createPanner();
      panner.panningModel = "equalpower";
      panner.setPosition(pan, 0, 1 - Math.abs(pan));
    }
    osc.connect(gain);
    gain.connect(panner);
    panner.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + BEEP_MS / 1000 + 0.02);
  },
};

function bytesOf(base64) {
  const text = atob(base64);
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i);
  return out;
}

async function sha256(bytes) {
  if (!(window.crypto && crypto.subtle)) return null;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function load(entry) {
  const bytes = bytesOf(entry.bytes);
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return { ...entry, screenPan: instance.exports.screen_pan, computed: await sha256(bytes) };
}

function moduleRow(m) {
  const tr = document.createElement("tr");
  const check = m.computed === null
    ? '<span class="muted">(this browser cannot hash it here)</span>'
    : m.computed === m.sha256
      ? '<span class="ok">matches the recorded hash</span>'
      : '<span class="bad">DIFFERS from the recorded hash ' + m.sha256 + "</span>";
  tr.innerHTML = "<td>" + m.label + "</td><td>" + m.model + "<br><code>" + m.reply + "</code></td>"
    + "<td><code>" + (m.computed || m.sha256) + "</code><br>" + check + "</td>";
  return tr;
}

async function main() {
  const original = await load(PAN_MODULES.original);
  const reversed = await load(PAN_MODULES.reversed);
  $("modules").append(moduleRow(original), moduleRow(reversed));

  let active = original;
  let playing = true;
  let started = performance.now();
  let pausedAt = 0;
  let lastBeep = -Infinity;

  function setMode(next) {
    active = next;
    $("mode-original").setAttribute("aria-pressed", String(next === original));
    $("mode-reversed").setAttribute("aria-pressed", String(next === reversed));
  }
  $("mode-original").onclick = () => setMode(original);
  $("mode-reversed").onclick = () => setMode(reversed);

  // Synchronous on purpose: Safari keeps the gesture only until the first
  // await.
  $("sound").onclick = () => {
    sound.set(!sound.on);
    $("sound").textContent = sound.on ? "Sound: on" : "Sound: off";
    $("sound").setAttribute("aria-pressed", String(sound.on));
  };
  document.addEventListener("pointerdown", () => { if (sound.on) sound.resume(); });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && sound.on) sound.resume();
  });

  $("pause").onclick = () => {
    playing = !playing;
    if (playing) started += performance.now() - pausedAt; else pausedAt = performance.now();
    $("pause").textContent = playing ? "Pause" : "Play";
  };

  function frame(now) {
    const elapsed = (playing ? now : pausedAt) - started;
    const phase = elapsed % (SWEEP_MS + PAUSE_MS);
    const x = Math.round(640 * Math.min(1, phase / SWEEP_MS));   // integer, 0 through 640
    const value = active.screenPan(x);                             // the one call the host makes

    const stage = $("stage").clientWidth;
    const left = 16 + (stage - 32) * (x / 640);
    $("ball").style.left = left + "px";
    const reading = $("reading");
    reading.textContent = "x = " + x + "\nscreen_pan(x) = " + value;
    // Beside the ball, but never past either side of the stage.
    const half = reading.offsetWidth / 2 + 8;
    reading.style.left = Math.max(half, Math.min(stage - half, left)) + "px";
    $("mark").style.left = (50 + 50 * clamp(value / PAN_RANGE)) + "%";

    if (playing && phase < SWEEP_MS && elapsed - lastBeep >= BEEP_EVERY_MS) {
      lastBeep = elapsed;
      sound.beep(clamp(value / PAN_RANGE));
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

main().catch((e) => {
  document.querySelector("main").insertAdjacentHTML("afterbegin",
    '<p class="bad">The modules could not be loaded: ' + e + "</p>");
});
