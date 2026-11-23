# Hear the change one byte makes in DX-Ball

Watch a ball travel from left to right. At first, a beep follows it from your left speaker to your right. Flip one switch and the ball keeps going the same way, but the beep travels the other way.

**Claude wrote the part that decides where the beep comes from.** We gave it an English description of a sound rule from the game DX-Ball. Its reply was a tiny program the browser could run directly. When we asked Claude Sonnet to reverse the sound, it changed one byte of its original 76-byte answer.

![Silent replay of the experiment. The ball and sound markers move together in Original mode and in opposite directions in Reversed mode.](media/dx-ball-pan-replay.gif)

## Hear it

1. With the demo open, turn **Sound** on. Headphones or stereo speakers make the difference easiest to hear.
2. Leave **Original** selected for one sweep. When the ball reaches the right edge, the beep comes from the right.
3. Select **Reversed** and watch the next sweep. This time, when the ball reaches the right edge, the beep comes from the left. With sound muted, follow the marker below the ball. It shows where the browser sends the beep.

**To open the demo locally**, run this from the repository folder with Erlang/OTP 29 or later and rebar3 installed. It checks the saved replies and opens the demo in your browser. You can try it without a model account or the game.

```sh
bin/wasm-bytes pan-demo
```

## What did the model actually do?

**First we asked for a rule.** The REA project had worked out how DX-Ball turns a screen position into a number for its sound system. We described that calculation to Claude and asked for a WebAssembly (Wasm) file as pairs of hexadecimal digits. Those digits spell out the program, byte by byte. The browser runs it by passing in the ball’s position and reading one number back. [Prompt sent to Sonnet](../trials/pan/claude-sonnet-5-5-1/prompt.txt) · [Its reply](../trials/pan/claude-sonnet-5-5-1/reply.txt)

**Then we asked for a change.** We gave Sonnet its own bytes and asked it to flip the sign of the answer. At the right edge, the original program returns 500 and the revised one returns −500. The demo sends positive values right and negative values left. At the center, both programs return zero, so the beep stays in the middle. The browser handles the animation and plays the same beep in both modes. [Change request](../trials/reverse/claude-sonnet-5-5-1/prompt.txt) · [Revised reply](../trials/reverse/claude-sonnet-5-5-1/reply.txt)

## How do we know it worked?

We checked every whole-number position from the left edge (0) to the right edge (640). Three models each tried the original task and the change once. All six replies gave the expected answer at all 641 positions in two independent Wasm runtimes, erlang_wasm and Wasmtime.

The comparison used the calculation REA recovered. The original game executable was unavailable, so the experiment establishes what these modules return. How DX-Ball sounded on its original hardware remains an open question. [Sources, test results, and replay commands](dx-ball-evidence.md)
