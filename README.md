# Can Claude write a WebAssembly file byte by byte?

The first test was a tiny program that tells an app when to try a request again: yes after “too many requests” (429) or a server error (500 to 599), no for anything else. The prompt asked for a complete WebAssembly (Wasm) file, with no compiler in between. Claude sent back 54 bytes. Here’s what happened when they ran.

- `retry(429)` → 1, try again
- `retry(404)` → 0, stop

The checker ran the bytes on 528 inputs, and every answer was right. Wasmtime, a second Wasm engine, ran the same bytes and agreed on all 528.

[See the prompt](trials/write/claude-sonnet-5-5-1/prompt.txt) · [See the bytes](trials/write/claude-sonnet-5-5-1/reply.txt) · [See how they were checked](doc/evidence.md) · [Try it yourself](doc/try.md)

## What came next

- **Adding up digits.** A bigger program, with a loop: `digit_sum(407)` returns 11. Opus, Sonnet and Haiku each wrote one that got all 1,353 test numbers right. [See the results](doc/status.md#adding-up-a-numbers-digits)
- **Sound in an old game.** The REA team pulled DX-Ball’s rule for playing a sound left or right out of the 1996 game. A prompt gave Claude that rule, and Claude wrote the Wasm the demo runs. To swap the speakers, Sonnet changed a single byte. [Hear the demo](https://benoitc.github.io/wasm-bytes/demo/pan/) · [Read the story](doc/dx-ball.md)
- **The demo page.** Another prompt asked the models to write the demo page itself, twice: first saying only what the page does, then also how it looks. Every page Claude wrote passed all 13 browser checks. [Hear the second attempts](https://benoitc.github.io/wasm-bytes/demo/ui/#second-attempts) · [Hear the first attempts](https://benoitc.github.io/wasm-bytes/demo/ui/#first-attempts)
- **599 questions.** Each one asks Claude Sonnet to read a file’s bytes and say what it returns, or to write a file that passes tests. Sonnet read 544 of 556 files right and wrote 30 of 31 single-operation programs, but solved only 7 of 12 contest problems. The whole run cost about $8.45. [See what it got right and wrong](doc/datasets.md)

Every reply is saved, so anyone can rerun the checks without an AI account. [See all the results](doc/status.md)

The idea comes from George Xenos and Sotiris Giannopoulos, who had models write native programs byte by byte. [Read their write-up](https://sgiannopoulos.github.io/blog/machine-code-programming/)
