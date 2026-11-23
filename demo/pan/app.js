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
  let audio = null;
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

  $("sound").onclick = async () => {
    if (!audio) audio = new AudioContext();
    if (audio.state === "running") {
      await audio.suspend();
    } else {
      await audio.resume();
    }
    const on = audio.state === "running";
    $("sound").textContent = on ? "Sound: on" : "Sound: off";
    $("sound").setAttribute("aria-pressed", String(on));
  };

  $("motion").onclick = () => {
    playing = !playing;
    if (playing) started += performance.now() - pausedAt; else pausedAt = performance.now();
    $("motion").textContent = playing ? "Pause" : "Play";
  };

  // The same beep in both modes; only the pan differs, and only because a
  // different module returned it.
  function beep(value) {
    if (!audio || audio.state !== "running") return;
    const t = audio.currentTime;
    const osc = new OscillatorNode(audio, { type: "sine", frequency: BEEP_HZ });
    const gain = new GainNode(audio, { gain: 0 });
    const pan = new StereoPannerNode(audio, { pan: Math.max(-1, Math.min(1, value / PAN_RANGE)) });
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(BEEP_GAIN, t + 0.005);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + BEEP_MS / 1000);
    osc.connect(gain).connect(pan).connect(audio.destination);
    osc.start(t);
    osc.stop(t + BEEP_MS / 1000 + 0.02);
  }

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
    $("mark").style.left = (50 + 50 * Math.max(-1, Math.min(1, value / PAN_RANGE))) + "%";

    if (playing && phase < SWEEP_MS && elapsed - lastBeep >= BEEP_EVERY_MS) {
      lastBeep = elapsed;
      beep(value);
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

main().catch((e) => {
  document.querySelector("main").insertAdjacentHTML("afterbegin",
    '<p class="bad">The modules could not be loaded: ' + e + "</p>");
});
