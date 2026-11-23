# What the first five trials showed

On 23 November 2026, three models each received the same prompt to write a WebAssembly function called `retry`. It should return 1 for HTTP status 429 and for 500 through 599, and 0 for every other 32-bit integer. The two models whose replies passed then received a second prompt containing their own bytes. This time they had to add 408 to the retry set and remove 501. [Write prompt](../prompts/write.txt) · [Revision prompt sent to Sonnet](../trials/revise/claude-sonnet-5-5-1/prompt.txt)

| Model | Write attempt | Revision attempt |
| --- | --- | --- |
| Claude Opus 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Sonnet 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Haiku 5.5 | 2 of 528 answers matched | No passing write reply to revise |

Opus and Sonnet each returned a working 54-byte module. Haiku also produced a module that ran, but its range check used an unsigned “greater than or equal to” comparison. For instance, it returned 1 for status 404 and 0 for status 500. You can inspect the three original replies. [Opus](../trials/write/claude-opus-5-5-1/reply.txt) · [Sonnet](../trials/write/claude-sonnet-5-5-1/reply.txt) · [Haiku](../trials/write/claude-haiku-5-5-1/reply.txt)

## How to interpret the results

Each result describes one attempt on one small function. The checker covers every HTTP status from 100 through 599 and 28 additional integers, including negative values and the limits of a 32-bit integer. A pass means the module met the interface requirements and produced the expected answer on those inputs. [How the checker works](runner.md)

All five trials used Claude Code with tools disabled, default sampling, and a replacement system prompt. The CLI still supplied some environment and account context. The same Opus model had also produced the passing write example while the checker was being built. Its recorded write reply matches that example byte for byte. The twelve examples under `examples/` were prepared to demonstrate checker behavior. The table counts only the five attempts with a recorded prompt, raw reply, and model identity. [Trial records](../trials/) · [Passing example](../examples/write/accepted/reply.txt)

## Replay or extend the experiment

Run `bin/wasm-bytes demo` from the repository root to replay the examples and trials. To try another model, send it the same write prompt and keep its reply intact. [First-run instructions](../README.md) · [How to record a trial](../trials/README.md)

The current tasks both ask for the complete module in hexadecimal. Planned comparisons include larger tasks, repeated attempts across providers, and asking for just the function body or for WebAssembly’s text format (WAT). The repository currently has no license file.
