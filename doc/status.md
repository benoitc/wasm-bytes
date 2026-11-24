# What we found

This page says what the models did in every experiment so far. It starts with the findings and why they matter, then gives the details of each run. Every number below comes from replies saved in this repository, and you can replay it without a model account.

## The findings

<div class="findings">

<div class="finding">
<h3>A model can write a working program as raw bytes, with no compiler.</h3>
<p class="evidence">528 of 528 · 1,353 of 1,353 · 641 of 641</p>
<p>Claude Opus and Sonnet wrote complete WebAssembly files, byte by byte, for three small functions. Each gave the right answer on every input we tried. Nothing sat between the model and the machine: the bytes it typed are the bytes that ran.</p>
<p class="refs"><a href="#a-small-function-retry">retry</a> · <a href="#a-slightly-larger-program-digit_sum">digit_sum</a> · <a href="#a-function-recovered-from-dx-ball">DX-Ball</a></p>
</div>

<div class="finding">
<h3>It can change its own program by exactly one byte.</h3>
<p class="evidence">1 byte changed, 640 answers changed, nothing else</p>
<p>Asked to reverse the stereo of the DX-Ball sound, Sonnet flipped one byte, <code>3f</code> to <code>bf</code>, turning a scale of 1.0 into −1.0. Every answer that should change did, and no other did. That is a precise edit to a compiled file, made without recompiling anything.</p>
<p class="refs"><a href="dx-ball.md">The DX-Ball story</a></p>
</div>

<div class="finding">
<h3>It can read a compiled program and say what it returns.</h3>
<p class="evidence">361 of 364 test-suite programs · 183 of 192 real files</p>
<p>Shown only the bytes, with no names or source code, Sonnet predicted the result of a call almost every time, including on real files collected from the web. That matters wherever you have a binary but no source: old software, like the DX-Ball game, or code you want to understand before you run it.</p>
<p class="refs"><a href="#reading-and-writing-tracks">Reading and writing</a></p>
</div>

<div class="finding">
<h3>Most reading mistakes were about format, not understanding.</h3>
<p class="evidence">8 of the 9 misses on real files were the right number</p>
<p>The model put the answer in bold Markdown, like <code>**11**</code>, where a bare number was asked for. The checker counts that as wrong, just as it counts a correct program with a sentence around it as wrong. A program reading the reply needs the exact format.</p>
<p class="refs"><a href="#reading-and-writing-tracks">The details</a></p>
</div>

<div class="finding">
<h3>Faced with a hash, it chose not to guess.</h3>
<p class="evidence">about 400,000 tokens of reasoning, then no answer</p>
<p>For a hash function that loops 100 times, Sonnet tried to work out the result by hand, then said it couldn't give a trustworthy number without running the code. That one question cost about $4, nearly half the full run. Knowing when not to answer is useful, but it isn't free.</p>
<p class="refs"><a href="#reading-and-writing-tracks">The details</a></p>
</div>

<div class="finding">
<h3>Harder problems are where writing bytes breaks.</h3>
<p class="evidence">30 of 31 single instructions · 7 of 12 contest problems</p>
<p>Writing a program for one instruction almost always worked. Contest problems need loops and arithmetic, and there the model solved the easier ones and about a third of the hard ones. Some replies weren't valid files at all. In the sample, both such files declared a section one byte longer than it was: the classic mistake when writing a binary by hand.</p>
<p class="refs"><a href="#reading-and-writing-tracks">The details</a></p>
</div>

<div class="finding">
<h3>A smaller model can catch up with a little guidance.</h3>
<p class="evidence">digit_sum: not a valid module without the guide, 1,353 of 1,353 with it</p>
<p>A local model, Inkling 2 Mini, picked wrong instruction bytes on its own. Given a one-page reference of the bytes for each instruction, it wrote a correct program. On the demo page, one extra paragraph about iPhone audio took it from 12 to 13 of 13 browser checks.</p>
<p class="refs"><a href="#a-guided-prompt-for-smaller-models">Guided prompts</a> · <a href="#a-demo-page-written-by-the-model">Demo pages</a></p>
</div>

<div class="finding">
<h3>All of this is cheap to run and quick to check.</h3>
<p class="evidence">599 questions · about 40 minutes · about $8.45</p>
<p>The full reading and writing run cost about $8.45 at list prices. Building the questions takes seconds, and checking every test-suite reply takes under a second. Every reply is saved, so anyone can check the results again without asking a model.</p>
<p class="refs"><a href="datasets.md#how-it-scales">How it scales</a></p>
</div>

</div>

These findings come mostly from Claude models, with one attempt per question. They show what happened on these questions, not how often a model succeeds in general. The same task can come out differently on a second try: the bitwise AND program passed in the sample and failed in the full run.

## A small function: retry

Opus and Sonnet each wrote a `retry` module that gave the expected answer for all 528 tested inputs. Asked to revise its own module, each changed only the answers for 408 and 501, as requested. Haiku's module ran but gave the expected answer for only 2 of the 528 inputs.

On 23 November 2026, three models each received the same prompt to write a WebAssembly function called `retry`. It should return 1 for HTTP status 429 and for 500 through 599, and 0 for every other 32-bit integer. The two models whose replies passed then received a second prompt containing their own bytes. This time they had to add 408 to the retry set and remove 501. [Write prompt](../prompts/write.txt) · [Revision prompt sent to Sonnet](../trials/revise/claude-sonnet-5-5-1/prompt.txt)

| Model | Write attempt | Revision attempt |
| --- | --- | --- |
| Claude Opus 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Sonnet 5.5 | 528 of 528 answers matched | Only 408 and 501 changed, as requested |
| Claude Haiku 5.5 | 2 of 528 answers matched | No passing write reply to revise |

Opus and Sonnet each returned a working 54-byte module. Haiku also produced a module that ran, but its range check used an unsigned “greater than or equal to” comparison. For instance, it returned 1 for status 404 and 0 for status 500. You can inspect the three original replies. [Opus](../trials/write/claude-opus-5-5-1/reply.txt) · [Sonnet](../trials/write/claude-sonnet-5-5-1/reply.txt) · [Haiku](../trials/write/claude-haiku-5-5-1/reply.txt)

## How to interpret the results

Each result describes one attempt on one small function. The checker covers every HTTP status from 100 through 599 and 28 additional integers, including negative values and the limits of a 32-bit integer. A pass means the module met the interface requirements and produced the expected answer on those inputs. [How the checker works](runner.md)

The tables count only attempts with a recorded prompt, raw reply, and model identity. The fourteen examples under `examples/` were prepared to demonstrate checker behavior. The same Opus model had also produced the passing write example while the checker was being built. The recorded Opus and Sonnet write replies both decode to exactly the bytes of that example, so all three share one SHA-256. Both trials ran without tools, so neither copied the example. The match does mean the example is not independent of the Opus trial. [Trial records](../trials/) · [Passing example](../examples/write/accepted/reply.txt)

<details>
<summary>How the trials were run</summary>

The Claude trials used Claude Code with tools disabled, default sampling, and a replacement system prompt. The CLI still supplied some environment and account context. The local trials used Ollama's chat API on this Mac, with the same system prompt, default sampling, and the model's default thinking level.

</details>

## A slightly larger program: digit_sum

All three Claude models wrote a `digit_sum` module that gave the expected answer for all 1,353 tested inputs. That includes Haiku, which had missed the smaller `retry` task. Each model had one attempt per task, so the difference says little about either model.

On 23 November 2026, the same three models each received one prompt for a larger function, `digit_sum`. It returns the sum of the decimal digits of a 32-bit integer and uses the digits of the absolute value for a negative number. For −2147483648 the answer is 47, the digit sum of 2147483648. A correct module needs a loop, a local variable, and unsigned division. The checker calls it on 1,353 inputs: every number from 0 through 1000, −1 through −100, each power of ten and its neighbours with both signs, the 32-bit limits, and 200 numbers spread over the whole range. [Prompt](../prompts/digits.txt) · [Inputs and reference](../src/wb_task.erl)

| Model | Module | Answers |
| --- | --- | --- |
| Claude Opus 5.5 | 90 bytes | 1,353 of 1,353 matched |
| Claude Sonnet 5.5 | 90 bytes | 1,353 of 1,353 matched |
| Claude Haiku 5.5 | 95 bytes | 1,353 of 1,353 matched |

All three modules negate a negative argument and then loop, adding the remainder of an unsigned division by ten. Opus and Sonnet sent the same 90 bytes. Haiku used one more local variable. The constructed example under `examples/digits/` matches none of the three modules. [Opus](../trials/digits/claude-opus-5-5-1/reply.txt) · [Sonnet](../trials/digits/claude-sonnet-5-5-1/reply.txt) · [Haiku](../trials/digits/claude-haiku-5-5-1/reply.txt)

## A guided prompt for smaller models

With a reference card added to the prompt, the local model Inkling 2 Mini wrote a `digit_sum` module that gave the expected answer for all 1,353 tested inputs, and a `retry` module that did so for 520 of 528. With the baseline prompts, neither of its modules could run: the `retry` module failed validation and the `digit_sum` module was malformed. The three Claude models gave the expected answer for every tested input with the guided prompts.

On 23 November 2026, a local model, Inkling 2 Mini (`inkling-2-mini:26b-a5b-nvfp4`, run through Ollama on this Mac), received both baseline prompts and then both guided prompts. The guided prompt keeps the task and adds a reference card: the module layout, how numbers are encoded, and the byte of each instruction with the order of its operands. It also asks for the work in numbered steps. The three Claude models received the guided prompts too. [Guided write prompt](../prompts/write.guided.txt) · [Guided digit_sum prompt](../prompts/digits.guided.txt)

<details>
<summary>The table, per model and prompt</summary>

Each cell is one attempt.

| Model | `retry`, baseline | `retry`, guided | `digit_sum`, baseline | `digit_sum`, guided |
| --- | --- | --- | --- | --- |
| Inkling 2 Mini, local | invalid module | 520 of 528 | malformed module | 1,353 of 1,353 |
| Claude Haiku 5.5 | 2 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Sonnet 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Opus 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |

</details>

With the baseline prompts, the local model laid out every section and length correctly but chose wrong instruction bytes. For `retry` it wrote `45` (`i32.eqz`) where `46` (`i32.eq`) belongs and reversed the range test, so its module failed validation. For `digit_sum` it used the byte `06`, which is not an instruction. With the reference card, its `digit_sum` module passed in erlang_wasm and in Wasmtime. Its `retry` module ran, but it encoded 500 as `ec 03`, which is 492, so it answers 1 for 492 through 499. The guided attempts took 7 and 10 minutes, against 10 and 40 for the baseline ones. [Baseline write](../trials/write/inkling-2-mini-1/) · [Guided write](../trials/write/inkling-2-mini-guided-1/) · [Baseline digit_sum](../trials/digits/inkling-2-mini-1/) · [Guided digit_sum](../trials/digits/inkling-2-mini-guided-1/)

Opus and Sonnet sent the same bytes with both prompts. Haiku's guided `retry` passed where its baseline attempt had not. With one attempt per model and prompt, these results cannot separate the effect of the prompt from the variation between attempts. Each local trial keeps the model's thinking trace in `thinking.txt`.

The local model also received the guided `pan` prompt once. Its 74-byte module is malformed. With no accepted `pan` module, it could not be given the `reverse` prompt, so no demo runs on local-model output alone yet. Its card adds the floating-point instructions and how a double is encoded, with examples other than the task's constants. The type section has no entry count, so the decoder reads `60` as 96 types, and the constant 1.0 is one byte short. It encoded 1.5625 and 500.0 correctly, and its instructions match the other models'. [Guided pan prompt](../prompts/pan.guided.txt) · [Its reply](../trials/pan/inkling-2-mini-guided-1/reply.txt)

## A function recovered from DX-Ball

Sonnet, Opus, and Haiku each wrote a `screen_pan` module that matched the published rule at all 641 positions (every x from 0 through 640), and each then reversed the stereo with exactly the 640 requested results changed. Those are this project's tests against the rule REA published. REA's own checks against the original game, 3,205 emulated x86 cases run by the reconstruction's differential test, are REA's work and were not repeated here, because the game's executable was unavailable. [REA's checks and ours](dx-ball-evidence.md#which-cases-can-be-checked)

On 23 November 2026, the three Claude models each received one prompt describing `screen_pan`. REA recovered this position-to-pan helper from DX-Ball's x86 code. Each model then received its own accepted bytes and a request to reverse the stereo. Each cell is one attempt, checked on every position from 0 through 640. [What REA recovered and which cases can be checked](dx-ball.md)

| Model | `pan` | `reverse` |
| --- | --- | --- |
| Claude Sonnet 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes |
| Claude Opus 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes |
| Claude Haiku 5.5 | 641 of 641 | 641 of 641, only the 640 requested changes |

All three `pan` replies are the same 76 bytes, which match the constructed example. Sonnet and Opus reversed the stereo by changing one byte, and Haiku by changing two. All six modules gave the same results in Wasmtime. [Trials](../trials/pan/) · [Revisions](../trials/reverse/)

## A demo page written by the model

Every page the models wrote passed all 13 browser checks, except the local model's first page, which passed 12 of 13 because it never asked for media playback on iOS. Its next page, from a guided prompt, passed all 13. These checks record what the page asks the browser to play, not what reaches a speaker, and the maintainer's report on 24 November that the sound plays on an iPhone did not record which pages they tried or the iOS version.

The models wrote the whole DX-Ball demo page, as one HTML file, in two rounds. A browser check drove each page in headless Chrome with the recorded modules, then with stand-in modules. [How a page is checked](ui.md)

On 23 November 2026, the first prompt said what the page does but not how it looks. Four of the five pages in this round passed all 13 checks.

<details>
<summary>First round: page size and verdict, per model</summary>

| Model | Page | Verdict |
| --- | --- | --- |
| Claude Sonnet 5.5 | 8,138 bytes | all 13 checks pass |
| Claude Opus 5.5 | 15,242 bytes | all 13 checks pass |
| Claude Haiku 5.5 | 7,456 bytes | all 13 checks pass |
| Inkling 2 Mini, local | 9,403 bytes | 12 of 13: no media playback requested for iOS |
| Inkling 2 Mini, local, guided prompt | 12,702 bytes | all 13 checks pass |

</details>

Every page called `screen_pan` on the selected module for each value it showed or played. Each kept its beeps identical across modes, turned the sound on with one tap, and fit a phone screen. Haiku's page asks for media playback only through the audio-session API of recent Safari. The check simulates that API, so it does not cover older iOS.

The local model's first page does everything else the prompt asks, but would probably be muted by an iPhone's silent switch. On 24 November, it received a guided prompt that adds one paragraph naming the audio-session API, and its new page passed all 13 checks. The paragraph says what to call, so the pass shows that the model follows it. One attempt cannot separate the paragraph's effect from the variation between attempts. [Trials](../trials/ui/)

On 24 November, a second prompt also described how the hand-written demo looks. The local model received its guided version. All four pages passed all 13 checks.

<details>
<summary>Second round: page size and verdict, per model</summary>

| Model | Page | Verdict |
| --- | --- | --- |
| Claude Sonnet 5.5 | 10,890 bytes | all 13 checks pass |
| Claude Opus 5.5 | 20,556 bytes | all 13 checks pass |
| Claude Haiku 5.5 | 12,804 bytes | all 13 checks pass |
| Inkling 2 Mini, local, guided prompt | 14,886 bytes | all 13 checks pass |

</details>

All four pages follow the described look closely. The checks do not compare the look, so that was judged by eye. Sonnet's page first got `ui_failed`, from a timing flaw in the `pause` check. The check now times its window from the click, and the unchanged page passes. [The second round](ui.md#with-the-look-described) · [Prompt](../prompts/ui.txt)

## Reading and writing tracks

On 24 November 2026, we asked Claude Sonnet 5.5 two new kinds of question, using public collections: read a WebAssembly file and say what a call returns, or write a working file from a description or a contest problem. Every right answer came from the collection itself. Sonnet answered a sample of 33 questions first, then all 599 usable ones, one attempt each. [What was asked, and how it scales](datasets.md)

| Question | Sample | Full run |
| --- | --- | --- |
| Read a test-suite program and predict a call | 12 of 12 right | 361 of 364 right |
| Write a program for one test-suite instruction | 8 of 8 passed | 30 of 31 passed |
| Read a real file from WasmBench and predict a call | 8 of 8 right | 183 of 192 right |
| Write a program for a contest problem | 1 of 5 passed | 7 of 12 passed |

What the numbers mean:

- **Reading small programs is close to solved for this model.** The three misses on the test suite involve unusual bit patterns, such as `0xf0f0f0f0` combined through `and` and `xor`.
- **On real files, format mattered as much as reasoning.** Eight of the nine misses were the right number, but in bold Markdown, and one of them came with an explanation. The checker accepts only a bare number, as it accepts only bare hex for a program. The ninth miss is a hash function: Sonnet reasoned for about 400,000 tokens, then said it couldn't answer without running the code.
- **One attempt isn't the whole story.** The bitwise AND program passed in the sample and failed in the full run. The contest problem Rubik's Cube Coloring went the other way.
- **Contest problems are the real test.** Sonnet solved every problem rated 7 to 9, and 2 of the 6 rated 10 to 12. One failure comes from the dataset, not the model: a generated test uses the input −27 for a problem whose limits are 1 to 32.

These results describe one model, one attempt per question, and small files. They show what happened on these questions, not how often a model succeeds in general.

<details>
<summary>How each sample and the full run were drawn, and what they cost</summary>

| Source | Looked at | Usable | Skipped, and why |
| --- | --- | --- | --- |
| WebAssembly test suite | 374 tests in `i32.wast` at testsuite `92a3d80` | 364 reading, 31 writing | 10 tests expect the call to fail, so there is no number to predict |
| WasmBench | 8,461 files in the v1.0 filtered release | 192 | 7,612 larger than 2,048 bytes; 540 that import functions; 99 without a function of up to two integers; 17 with no call that returned; 1 that cannot be instantiated |
| CodeContests | 624 problems in the valid, test, and first training files at revision `802411c` | 12 | 594 whose input is not one or two integers; 12 whose output is not one integer; 5 with a value beyond 32 bits; 1 with tests that disagree |

Each sample takes the usable questions in the order of the SHA-256 of `"2026:<id>"`. The WasmBench sample only uses files from openly licensed projects, and the test-suite sample always includes the addition example. The full run used every usable question. Its replies are in `trials/corpus/`, and its questions are rebuilt from the pinned sources.

The full run took about 40 minutes, with the three sources side by side. It used 621,920 input and 690,551 output tokens, about $8.45 at list prices, $4.02 of it for the hash function alone. One WasmBench question was asked twice where two workers met; its record says so. [Full run summary](../trials/corpus/summary.config)

Replay any total with `bin/wasm-bytes batch TRACK LABEL`. The sample uses the label `claude-sonnet-5-5-1`. The full run uses `claude-sonnet-5-5-corpus-1`, with `--cases _build/cases --replies trials/corpus` after rebuilding its questions.

</details>

## Cross-engine and platform runs

The Sonnet `retry` module and the three `digit_sum` modules gave the reference answer for every tested input (528 and 1,353) in two engines, erlang_wasm and Wasmtime, on three host configurations of one Apple silicon Mac: macOS, Linux, and Linux with x86_64 emulated. These runs establish that the two engines agree on these modules on one host. A run on separate x86_64 hardware has not been recorded yet. [Commands, records, and limits](evidence.md)

<details>
<summary>Engine versions and the result on each host</summary>

On 23 November 2026, the Sonnet write module ran in erlang_wasm 0.11.0 and in Wasmtime 50.0.1 on all 528 inputs. Both engines gave the reference answer every time and reported the same SHA-256 for the bytes they received. This held on three host configurations, all on one Apple silicon Mac:

| Host | erlang_wasm | Wasmtime |
| --- | --- | --- |
| macOS 27.2, arm64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, aarch64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, x86_64 emulated | 528 of 528 | 528 of 528 |

The three `digit_sum` modules gave the same result: 1,353 of 1,353 in both engines on the same three host configurations. The result held on a second operating system and with the x86_64 builds of both engines.

</details>

## Replay or extend the experiment

Run `bin/wasm-bytes replay` from the repository root for the short account, or `bin/wasm-bytes demo` to replay every example and trial. To try another model, send it the same write prompt and keep its reply intact. [First-run instructions](../README.md) · [How to record a trial](../trials/README.md)

The current tasks both ask for the complete module in hexadecimal. Planned comparisons include larger tasks, repeated attempts across providers, and asking for just the function body or for WebAssembly’s text format (WAT).
