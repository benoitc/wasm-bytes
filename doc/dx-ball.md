# How we reused a sound rule from DX-Ball

In DX-Ball, a ball hits a brick and the game plays a sound. We wanted to reuse one part of that feature in a browser app: given the position of the hit, how far left or right should the sound play? This page follows one position, x = 640, the right edge of the screen, from REA's finding to the beep in your speaker.

**Do you need REA to run this? No.** What crossed from REA into this project is a description of what the old game did: the sound calculation. We used it to write a prompt, and the model wrote the WebAssembly (Wasm). REA generated no code here and does not run in the demo.

<!-- flow:start -->
## How we made it

<ol class="flow">
<li>
<div class="card">
<p class="what"><strong>REA studied the old game.</strong> REA's team inspected the DX-Ball executable and published how the game turns a brick's horizontal position into a number for its sound system.</p>
<p class="out">From the recovered calculation: 640 × 1.5625 − 500 = 500. Position 640 gives <strong>500</strong>.</p>
<p class="refs"><a href="https://github.com/morluto/rea#dx-ball-reconstruct-a-sound-pan-calculation">REA's case study</a> · <a href="https://github.com/morluto/rea/blob/3cfbe81509e4f33780a7d3ef843510e94e042495/website/evidence/dx-ball-sound-pan.md">Its evidence for this function</a></p>
</div>
</li>
<li>
<p class="via">We used the published calculation</p>
<div class="card">
<p class="what"><strong>We turned that finding into an English prompt.</strong> We supplied the math and asked for a complete WebAssembly file, written as hex. The model's job was to write the executable bytes, not to work out the rule.</p>
<blockquote class="excerpt">
<p class="excerpt-label">Excerpt from the prompt</p>
<p>It computes, in double-precision floating point: x times 1.5625, then minus 500.0, then times a scale of 1.0.</p>
<p>You write every byte […] the bytes you send are the bytes that run.</p>
</blockquote>
<p class="refs"><a href="../trials/pan/claude-sonnet-5-5-1/prompt.txt">Read the full prompt</a></p>
</div>
</li>
<li>
<p class="via">The prompt, sent to Claude Sonnet 5.5</p>
<div class="card">
<p class="what"><strong>Claude returned a 76-byte program.</strong> Decoding the hex gives a file the browser can load. Our checker ran it at every position from 0 through 640 and compared each answer with the recovered rule. All 641 answers matched.</p>
<p class="out"><code>00 61 73 6d 01 00 00 00</code> starts the file. Its last constant, <code>00 00 00 00 00 00 f0 3f</code>, is the scale 1.0. <code>screen_pan(640)</code> returns <strong>500</strong>.</p>
<p class="refs"><a href="../trials/pan/claude-sonnet-5-5-1/reply.txt">The complete reply</a> · <a href="dx-ball-evidence.md#what-the-models-wrote">How it was tested</a></p>
</div>
</li>
<li>
<p class="via">The accepted 76 bytes, and one request</p>
<div class="card">
<p class="what"><strong>We asked Claude to reverse the sound.</strong> The second prompt contained those bytes and one request: reverse the sign of the answer. Sonnet returned another 76-byte program with one byte changed. All 641 answers matched the reversed rule.</p>
<p class="out">The scale's last byte, <code>3f</code>, became <code>bf</code>: the scale is now −1.0. <code>screen_pan(640)</code> returns <strong>−500</strong>.</p>
<p class="refs"><a href="../trials/reverse/claude-sonnet-5-5-1/prompt.txt">The change request</a> · <a href="../trials/reverse/claude-sonnet-5-5-1/reply.txt">The revised reply</a></p>
</div>
</li>
</ol>

<div class="meet">
<div class="input">
<p class="via">Both programs, saved as returned</p>
<div class="card plain">
<p class="what"><strong>Two Wasm files.</strong> The Original and the Reversed program, 76 bytes each.</p>
</div>
<p class="via">Original + Reversed Wasm files</p>
</div>
<div class="input">
<div class="card plain">
<p class="what"><strong>A third prompt.</strong> A model writes the HTML page: the moving ball, the controls and the audio. The page loads the two Wasm files and contains neither.</p>
<p class="refs"><a href="../prompts/ui.txt">The page prompt</a> · <a href="https://benoitc.github.io/wasm-bytes/demo/ui/">Pages the models wrote</a></p>
</div>
<p class="via">HTML page</p>
</div>
</div>

<div class="card browser">
<p class="what"><strong>Your browser.</strong> It loads the HTML page and runs the two Wasm files beside it, on your machine. One model can write the page while another wrote the sound logic. The live demo's page was written by hand.</p>
</div>

## What happens when you play

<ol class="play">
<li>The ball reaches the right edge</li>
<li>The browser calls <code>screen_pan(640)</code></li>
<li>The selected file returns a number</li>
<li>The browser places the beep</li>
</ol>

<div class="outcomes">
<p class="outcome right"><strong>Original</strong> returns <code>500</code>: right speaker</p>
<p class="outcome left"><strong>Reversed</strong> returns <code>-500</code>: left speaker</p>
</div>

<p class="caption">Your browser runs the two saved files locally. You can play the demo without REA, Claude, or the original game. The left and right speaker mapping belongs to our demo: it divides the number by 500 and uses the result as the stereo position.</p>
<!-- flow:end -->

## Hear it

Open the live demo, turn **Sound** on, and watch the ball reach the right edge. Then select **Reversed**. Headphones make the change easy to hear. With sound muted, the marker below the ball shows where each beep would play. [Live demo](https://benoitc.github.io/wasm-bytes/demo/pan/)

![The ball moves right in both runs. The sound marker follows it with the original program and moves left with the revision.](media/dx-ball-pan-replay.gif)

To run it locally, use this command from the repository folder, with Erlang/OTP 29 or later and rebar3 installed. It checks the saved replies again and opens the demo in your browser.

```sh
bin/wasm-bytes pan-demo
```

## Both programs at three positions

The same app gets these answers, depending on which file it loads. The center stays at 0, and the two edges swap. [Test results and how to reproduce them](dx-ball-evidence.md)

| Where is the ball? | Original program | Reversed program |
| --- | --- | --- |
| Left edge (0) | −500 → left speaker | 500 → right speaker |
| Middle (320) | 0 → centered | 0 → centered |
| Right edge (640) | 500 → right speaker | −500 → left speaker |

## The prompt in full

The prompt gives the model the exact calculation: multiply the position by 1.5625, subtract 500, apply a scale of 1, and drop the fractional part. So the model already knows **what answer to calculate**. Its job is to write **the program that calculates it**, including every byte the browser needs to load it. Hex writes each byte as two characters, so the bytes fit in a chat reply.

<details>
<summary>Read the complete prompt sent to Claude</summary>

```text
Write a complete WebAssembly module in the binary format (the bytes of a
.wasm file, version 1) and reply with its bytes as hex.

The module implements a function recovered from the x86 code of the game
DX-Ball (version 1.07, 1996). The game calls it with the horizontal screen
position of something that makes a sound, such as a brick that was hit, and
passes the result to its sound routine as a stereo pan value, so that the
sound comes from that side of the screen.

The module exports one function, named "screen_pan", with one i32 parameter
and one i32 result:

  screen_pan(x) takes a horizontal screen position x, from 0 at the left
  edge through 640 at the right edge.
  It computes, in double-precision floating point: x times 1.5625, then
  minus 500.0, then times a scale of 1.0.
  It converts that value to an i32 by truncating toward zero: any fraction
  is dropped, for negative values as for positive ones.
  The result goes from -500 at the left edge to 500 at the right edge. A
  negative value is left of centre, a positive value right of centre.

The module has exactly one function, the exported one, and exports nothing
else. It has no imports, no memory and no start function.

You write every byte: the magic number and version, every section id, every
section length, every function body length, every local declaration and
every instruction. Nothing will be added to your bytes and no length will be
corrected: the bytes you send are the bytes that run.

Reply with only the bytes, as pairs of hexadecimal digits, for example:

0f a0 7c

Whitespace and line breaks between pairs are allowed. Do not split a pair.
Do not add anything else: no explanation, no code fence, no 0x prefix, no
comments.
```

</details>

## What REA found, and what it checked

REA is a tool that helps you understand how existing software works by inspecting the compiled program. The REA project examined the instructions in the DX-Ball executable and identified the calculation the game uses when it passes a brick's position to its sound system. With the game's usual settings, a hit at the left edge gives −500, the middle gives 0, and the right edge gives 500.

REA's case study shows the original instructions beside the same rule written in C. Its reconstruction checks that C rule against the old game code, which needs the game's executable. Those checks are REA's. This project did not have the executable, so it tested each program against the published rule instead: every position from 0 through 640. [REA's evidence for this function](https://github.com/morluto/rea/blob/3cfbe81509e4f33780a7d3ef843510e94e042495/website/evidence/dx-ball-sound-pan.md) · [What each side checked](dx-ball-evidence.md)

## What a developer gets out of this

Say you're moving a feature from an old desktop app to the web. REA's analysis can tell you what the old feature did and give you expected answers to test against. This experiment shows the next step for one small rule: ask a model for a file your new app can load, test it, then call it wherever you need that decision. Once you have the file, each call runs locally. You don't need to ask Claude again every time the ball moves.

You can also change the rule while keeping the app code that uses it. Here, the app switches which file it loads. Both versions accept the same position and return one number, so the drawing and audio code work with either.

Before the demo opens, erlang_wasm checks that each file is a valid program and runs it under time and work limits. All six recorded replies (an original and a reversal from each of three Claude models) matched the published rule at all 641 positions, in both erlang_wasm and Wasmtime. These results cover this one calculation. They don't show agreement with the original game's own runs, which needs the executable. [Test results and how to reproduce them](dx-ball-evidence.md)
