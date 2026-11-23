# What the recorded trials showed

On 23 November 2026, three models each received the same prompt to write a WebAssembly function called `retry`. It should return 1 for HTTP status 429 and for 500 through 599, and 0 for every other 32-bit integer. The two models whose replies passed then received a second prompt containing their own bytes. This time they had to add 408 to the retry set and remove 501. [Write prompt](../prompts/write.txt) · [Revision prompt sent to Sonnet](../trials/revise/claude-sonnet-5-5-1/prompt.txt)

| Model | Write attempt | Revision attempt |
| --- | --- | --- |
| Claude Opus 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Sonnet 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Haiku 5.5 | 2 of 528 answers matched | No passing write reply to revise |

Opus and Sonnet each returned a working 54-byte module. Haiku also produced a module that ran, but its range check used an unsigned “greater than or equal to” comparison. For instance, it returned 1 for status 404 and 0 for status 500. You can inspect the three original replies. [Opus](../trials/write/claude-opus-5-5-1/reply.txt) · [Sonnet](../trials/write/claude-sonnet-5-5-1/reply.txt) · [Haiku](../trials/write/claude-haiku-5-5-1/reply.txt)

## How to interpret the results

Each result describes one attempt on one small function. The checker covers every HTTP status from 100 through 599 and 28 additional integers, including negative values and the limits of a 32-bit integer. A pass means the module met the interface requirements and produced the expected answer on those inputs. [How the checker works](runner.md)

The Claude trials used Claude Code with tools disabled, default sampling, and a replacement system prompt. The CLI still supplied some environment and account context. The local trials used Ollama's chat API on this Mac, with the same system prompt, default sampling, and the model's default thinking level. The same Opus model had also produced the passing write example while the checker was being built. The recorded Opus and Sonnet write replies both decode to exactly the bytes of that example, so all three share one SHA-256. Both trials ran without tools, so neither copied the example. The match does mean the example is not independent of the Opus trial. The fourteen examples under `examples/` were prepared to demonstrate checker behavior. The tables count only attempts with a recorded prompt, raw reply, and model identity. [Trial records](../trials/) · [Passing example](../examples/write/accepted/reply.txt)

## A slightly larger program: digit_sum

On 23 November 2026, the same three models each received one prompt for a larger function, `digit_sum`. It returns the sum of the decimal digits of a 32-bit integer and uses the digits of the absolute value for a negative number. For −2147483648 the answer is 47, the digit sum of 2147483648. A correct module needs a loop, a local variable, and unsigned division. The checker calls it on 1,353 inputs: every number from 0 through 1000, −1 through −100, each power of ten and its neighbours with both signs, the 32-bit limits, and 200 numbers spread over the whole range. [Prompt](../prompts/digits.txt) · [Inputs and reference](../src/wb_task.erl)

| Model | Module | Answers |
| --- | --- | --- |
| Claude Opus 5.5 | 90 bytes | 1,353 of 1,353 matched |
| Claude Sonnet 5.5 | 90 bytes | 1,353 of 1,353 matched |
| Claude Haiku 5.5 | 95 bytes | 1,353 of 1,353 matched |

All three modules negate a negative argument and then loop, adding the remainder of an unsigned division by ten. Opus and Sonnet sent the same 90 bytes. Haiku used one more local variable. Haiku missed the smaller `retry` task but passed this one. Each model had one attempt per task, so the difference says little about either model. The constructed example under `examples/digits/` matches none of the three modules. [Opus](../trials/digits/claude-opus-5-5-1/reply.txt) · [Sonnet](../trials/digits/claude-sonnet-5-5-1/reply.txt) · [Haiku](../trials/digits/claude-haiku-5-5-1/reply.txt)

## A guided prompt for smaller models

On 23 November 2026, a local model, Inkling 2 Mini (`inkling-2-mini:26b-a5b-nvfp4`, run through Ollama on this Mac), received both baseline prompts and then both guided prompts. The guided prompt keeps the task and adds a reference card: the module layout, how numbers are encoded, and the byte of each instruction with the order of its operands. It also asks for the work in numbered steps. The three Claude models received the guided prompts too. Each cell is one attempt. [Guided write prompt](../prompts/write.guided.txt) · [Guided digit_sum prompt](../prompts/digits.guided.txt)

| Model | `retry`, baseline | `retry`, guided | `digit_sum`, baseline | `digit_sum`, guided |
| --- | --- | --- | --- | --- |
| Inkling 2 Mini, local | invalid module | 520 of 528 | malformed module | 1,353 of 1,353 |
| Claude Haiku 5.5 | 2 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Sonnet 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Opus 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |

With the baseline prompts, the local model laid out every section and length correctly but chose wrong instruction bytes. For `retry` it wrote `45` (`i32.eqz`) where `46` (`i32.eq`) belongs and reversed the range test, so its module failed validation. For `digit_sum` it used the byte `06`, which is not an instruction. With the reference card, its `digit_sum` module passed in erlang_wasm and in Wasmtime. Its `retry` module ran, but it encoded 500 as `ec 03`, which is 492, so it answers 1 for 492 through 499. The guided attempts took 7 and 10 minutes, against 10 and 40 for the baseline ones. [Baseline write](../trials/write/inkling-2-mini-1/) · [Guided write](../trials/write/inkling-2-mini-guided-1/) · [Baseline digit_sum](../trials/digits/inkling-2-mini-1/) · [Guided digit_sum](../trials/digits/inkling-2-mini-guided-1/)

Opus and Sonnet sent the same bytes with both prompts. Haiku's guided `retry` passed where its baseline attempt had not. With one attempt per cell, these results cannot separate the effect of the prompt from the variation between attempts. Each local trial keeps the model's thinking trace in `thinking.txt`.

## Cross-engine and platform runs

On 23 November 2026, the Sonnet write module ran in erlang_wasm 0.11.0 and in Wasmtime 50.0.1 on all 528 inputs. Both engines gave the reference answer every time and reported the same SHA-256 for the bytes they received. This held on three host configurations, all on one Apple silicon Mac:

| Host | erlang_wasm | Wasmtime |
| --- | --- | --- |
| macOS 27.2, arm64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, aarch64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, x86_64 emulated | 528 of 528 | 528 of 528 |

The three `digit_sum` modules gave the same result: 1,353 of 1,353 in both engines on the same three host configurations. These runs establish that the two engines agree on these modules on one host. The result held on a second operating system and with the x86_64 builds of both engines. A run on separate x86_64 hardware has not been recorded yet. [Commands, records, and limits](evidence.md)

## Replay or extend the experiment

Run `bin/wasm-bytes replay` from the repository root for the short account, or `bin/wasm-bytes demo` to replay every example and trial. To try another model, send it the same write prompt and keep its reply intact. [First-run instructions](../README.md) · [How to record a trial](../trials/README.md)

The current tasks both ask for the complete module in hexadecimal. Planned comparisons include larger tasks, repeated attempts across providers, and asking for just the function body or for WebAssembly’s text format (WAT).
