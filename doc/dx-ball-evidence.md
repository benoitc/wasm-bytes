# DX-Ball experiment records

The [demo guide](dx-ball.md) explains what to listen for and how to try it. These records describe the sources, model replies, and checks from 23 November 2026.

## What REA recovered

REA's showcase links its evidence to a separate reconstruction repository. This experiment read both at these revisions:

| Source | Revision | What it provides |
| --- | --- | --- |
| [REA](https://github.com/morluto/rea#dx-ball-reconstruct-a-sound-pan-calculation) | `3cfbe81509e4f33780a7d3ef843510e94e042495` | The showcase, and `website/evidence/dx-ball-sound-pan.md` with the recorded instruction listing and constants |
| [DX-Ball reconstruction](https://github.com/N0zoM1z0/dx-ball) | `a55dca27ec0a07018c1b2c95ae2be027f7d8c3c4` (7 October 2026) | The commit REA's evidence is pinned to: the maintained C function, its callers, and the differential test |

The maintained function is unchanged at the reconstruction's later commit `e2a633f`. Neither repository includes the game's executable. Nothing from the game itself is in this repository.

The function is the 63 bytes at `0x406400` through `0x40643e` in `DXBALL.EXE` 1.07 (158,208 bytes, SHA-256 `756da1ba09edce716d5bf8770320ca0d5ed4e525672b6bb605b9bdb4b88972ba`). REA recorded the following:

- **Input.** One integer, read from the stack, a horizontal screen position. A brick hit passes `30 × column + 20` for columns 0 through 19, so 20 through 590. A bonus pickup passes `30 × column + 19`.
- **Calculation.** `FILD` the input, `FMUL` by the double 1.5625, `FSUB` the double 500.0, `FMUL` by a stored double, then `__ftol`. REA read the two constants and the stored double's initial value, 1.0, from the game's data. The reconstruction names that double `dxball_pan_scale`. Nothing in the reconstructed source changes it.
- **Output.** An integer, truncated toward zero. With the scale at 1.0, it runs from −500 at x = 0 through 0 at x = 320 to 500 at x = 640.
- **What the game does with it.** The caller passes it as the `pan` argument of `play_sound(sound, repeat, pan, volume)`. The game's sound code, which uses DirectSound, is marked "pending" in the reconstruction. So the unit of the value and the direction of each side are not established. With DirectSound's `SetPan`, the unit would be hundredths of a decibel, and ±500 would be a 5 dB difference between the sides. That reading is plausible, but no recorded evidence confirms it.

## Which cases can be checked

REA reports 3,205 original-x86 cases: every integer x from 0 through 640, at scales 0, 0.5, 1, 20 and −1. They are not stored as data. The reconstruction's `tests/test_gameplay_differential.py` regenerates them. It runs the original function from `DXBALL.EXE` in the Unicorn CPU emulator and compares each result with the maintained C function. That harness needs the user-supplied executable with the hash above. It was not available here, so no original-x86 result was checked in this experiment.

This experiment checks the 641 positions at scale 1.0 instead. Its reference is the expression REA recorded, in Erlang: `trunc((x × 1.5625 − 500.0) × 1.0)`. Every step is exact in double precision for these inputs. The x87 unit's wider intermediate precision therefore cannot change any of the 641 results. The other 2,564 cases set the scale to values the game never uses, so they fall outside this interface. Anyone who has the executable can run the reconstruction's harness at its pinned commit to compare the original code with the same expression. [Reference and inputs](../src/wb_task.erl)

## What the model was asked

The `pan` prompt describes the recovered behavior in words. It covers what the game uses the function for, the input range, each operation with its constant, truncation toward zero, and the output range. It also gives the exact interface, `screen_pan : (i32) -> (i32)`. It includes neither the reference code nor any test case. [Pan prompt](../prompts/pan.txt)

The `reverse` prompt holds the model's own accepted bytes, the unchanged interface, and one change request: return the current value with its sign reversed. In the recovered representation, negative values are left of center and positive values right of center. Reversing the sign therefore swaps the sides and leaves the center at 0. For each whole position x, this also equals the original value at the mirrored position, 640 − x. [Reverse prompt template](../prompts/reverse.txt)

## What the models wrote

Three models each received each prompt once, through the Claude Code CLI with tools off. Every attempt is recorded under `trials/pan/` and `trials/reverse/`, with its prompt, raw reply, model identity, and verdict.

| Model | `pan` | `reverse` | Revised bytes |
| --- | --- | --- | --- |
| Claude Sonnet 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes | `070cf254…`, one byte changed |
| Claude Opus 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes | `070cf254…`, one byte changed |
| Claude Haiku 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes | `3bcada5c…`, two bytes changed |

All three `pan` replies decode to the same 76 bytes, SHA-256 `11aa6fd76525b13b2cd0998ac5f65154ecebfd1377091df117cd7dcd8f4058ea`. They convert x to a double, multiply, subtract, multiply, and truncate. They write the three constants as `00 00 00 00 00 00 f9 3f`, `00 00 00 00 00 40 7f 40` and `00 00 00 00 00 00 f0 3f`, the same bytes REA read from the game's data. Sonnet and Opus reversed the stereo by changing the scale from 1.0 to −1.0, one byte from `3f` to `bf`. Haiku negated 1.5625 and 500.0 instead, which computes 500 − 1.5625 × x.

The constructed example `examples/pan/accepted` has the same 76 bytes as the three `pan` replies. Opus 5.5 assembled it while building the checker. All three trials ran with no tools and no files, so they did not copy it. Another constructed example shows the checker catching a near miss. [Integer-division example](../examples/pan/integer-division/)

Run this to replay both checks of the Sonnet pair. It checks the `pan` reply again as the base, then the revision:

```sh
bin/wasm-bytes check reverse trials/reverse/claude-sonnet-5-5-1/reply.txt --base trials/pan/claude-sonnet-5-5-1/reply.txt
```

```text
  base     trials/pan/claude-sonnet-5-5-1/reply.txt: 76 bytes, passes the pan task
  diff     76 -> 76 bytes, 1 hunk
           @ base 0x0048, revised 0x0048: function body 0
             - 3f
             + bf
  changes  640 of 641 inputs changed result
           0: -500 -> 500  (requested)
           640: 500 -> -500  (requested)
  request  done: all 640 requested changes; no other result changed
  verdict  pass
```

## The same bytes in Wasmtime

Every recorded module ran in erlang_wasm 0.11.0 and Wasmtime 50.0.1 on the same 641 positions. Each engine hashed the bytes it received. This needs Wasmtime installed.

```sh
bin/wasm-bytes compare pan trials/pan/claude-sonnet-5-5-1/reply.txt
bin/wasm-bytes compare reverse trials/reverse/claude-sonnet-5-5-1/reply.txt
```

```text
  module       76 bytes, sha256 11aa6fd76525b13b2cd0998ac5f65154ecebfd1377091df117cd7dcd8f4058ea
  erlang_wasm  0.11.0, received the same bytes: 641 of 641 match the reference
  wasmtime     50.0.1, received the same bytes: 641 of 641 match the reference
  verdict      pass
```

All six modules passed in both engines on macOS arm64. The Sonnet pair also passed in a Linux arm64 container. Each run wrote a record with the host, runtime versions, module hash, and result. [Run records](../evidence/runs/)

## Browser playback

The demo maps the returned value to the stereo control by dividing it by 500. A value of −500 sends the beep fully left and 500 sends it fully right. This is a choice made by the demo. The browser check covered motion, switching modules at a paused position, and the recorded hashes. Listening to the audio requires a person. [Host page](../demo/pan/index.html) · [Host script](../demo/pan/app.js)

To try other recorded modules, pass their reply files to `pan-demo` with `--original` and `--reversed`. Use `--no-open` to build the page without launching a browser.

## What the evidence supports

**Supported**, for this function, these 641 positions, and one attempt per model:

- Three Claude models implemented the behavior REA recovered as complete WebAssembly modules from an English description. Each module passed validation, the interface rules, and every position.
- Each model revised its own accepted bytes to reverse the stereo. Exactly the 640 requested results changed.
- The same bytes gave the same results in erlang_wasm and in Wasmtime, on macOS and on Linux.
- The demo changes nothing but the module that answers `screen_pan(x)`.

**Not established:**

- Agreement with the original game's executed results. That needs the executable, which was not available.
- How the game's sound code uses the value: its unit, and which side a negative value plays on.
- Behavior at scales other than 1.0, other models, repeated attempts, and larger recovered functions.
