# What we found

This page is the scoreboard of the experiment. In each task, an AI model writes a small program, or reads one, as raw WebAssembly (Wasm) bytes, with no compiler to help. A checker then runs the program on hundreds of inputs and counts the right answers. A program passes only if every answer is right. The headline numbers come first, then what they mean, then the details of every run. Every number comes from replies saved in this repository, so you can check it again yourself, without an account with any AI company.

## The numbers at a glance

<div class="kpis">
<div class="kpi">
<p class="kpi-label">Small programs written right</p>
<p class="kpi-value">3 of 3</p>
<p class="kpi-note">By Claude Opus and Sonnet, each right on every input tried</p>
</div>
<div class="kpi">
<p class="kpi-label">Files read right</p>
<p class="kpi-value">98%</p>
<p class="kpi-note">544 of 556: from the bytes alone, Sonnet said what the file returns</p>
</div>
<div class="kpi">
<p class="kpi-label">Contest problems solved</p>
<p class="kpi-value">58%</p>
<p class="kpi-note">7 of 12: harder problems are where it breaks</p>
</div>
<div class="kpi">
<p class="kpi-label">Cost of 599 questions</p>
<p class="kpi-value">$8.45</p>
<p class="kpi-note">About 40 minutes, and every reply is saved</p>
</div>
</div>

## How each model did on the small programs

Each cell is one attempt. Opus, Sonnet and Haiku are Claude models. Inkling 2 Mini is a smaller model that runs on a laptop. “With a guide” means a second attempt with a one-page reference added to the prompt.

| What the model was asked | Opus 5.5 | Sonnet 5.5 | Haiku 5.5 | Inkling 2 Mini |
| --- | --- | --- | --- | --- |
| [Decide whether to retry](#deciding-whether-to-retry), 528 inputs | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="no">✗</span>&nbsp;2 of 528 right<br>With a guide: <span class="ok">✓</span>&nbsp;pass | <span class="no">✗</span>&nbsp;not a valid file<br>With a guide: <span class="no">✗</span>&nbsp;520 of 528 right |
| Change that program on request | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | Not tried: no passing program | Not tried: no passing program |
| [Add up a number's digits](#adding-up-a-numbers-digits), 1,353 inputs | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="no">✗</span>&nbsp;not a valid file<br>With a guide: <span class="ok">✓</span>&nbsp;pass |
| [Place a game sound left or right](#placing-a-game-sound-left-or-right), 641 positions | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | With a guide: <span class="no">✗</span>&nbsp;not a valid file |
| Swap that sound's left and right | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | Not tried: no passing program |
| [Write the demo web page](#writing-the-demo-web-page), 13 browser checks | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="ok">✓</span>&nbsp;pass | <span class="no">✗</span>&nbsp;12 of 13 checks<br>With a guide: <span class="ok">✓</span>&nbsp;pass |

## How Sonnet did on 599 public questions

Claude Sonnet 5.5 answered every usable question from three public collections, one attempt each. The right answers come from the collections, not from us. [Reading and writing at scale](#reading-and-writing-at-scale)

<div class="meters">
<div class="meter" title="361 of 364 right"><span class="meter-name">Read a small test program, predict the answer</span><span class="meter-bar" aria-hidden="true"><span style="width:99.2%"></span></span><span class="meter-fig">361 of 364</span></div>
<div class="meter" title="183 of 192 right"><span class="meter-name">Read a real file from the web, predict the answer</span><span class="meter-bar" aria-hidden="true"><span style="width:95.3%"></span></span><span class="meter-fig">183 of 192</span></div>
<div class="meter" title="30 of 31 passed"><span class="meter-name">Write a program for one operation</span><span class="meter-bar" aria-hidden="true"><span style="width:96.8%"></span></span><span class="meter-fig">30 of 31</span></div>
<div class="meter" title="7 of 12 passed"><span class="meter-name">Write a program for a contest problem</span><span class="meter-bar" aria-hidden="true"><span style="width:58.3%"></span></span><span class="meter-fig">7 of 12</span></div>
</div>

## What the numbers tell you

<div class="findings">

<div class="finding">
<h3>A model can write a working program as raw bytes.</h3>
<p>Claude Opus and Sonnet wrote complete Wasm files, one byte at a time, for three small programs. Each gave the right answer on every input we tried. No compiler sat in between: the bytes the model typed are the bytes that ran.</p>
<p class="refs"><a href="#deciding-whether-to-retry">Retry</a> · <a href="#adding-up-a-numbers-digits">Digits</a> · <a href="#placing-a-game-sound-left-or-right">Game sound</a></p>
</div>

<div class="finding">
<h3>It can make a precise change to its own program.</h3>
<p>Asked to swap the game sound's left and right, Sonnet changed a single byte, <code>3f</code> to <code>bf</code>, which turns 1.0 into −1.0. Every answer that should change did, and nothing else changed. That is an exact edit to a finished program, with nothing rebuilt.</p>
<p class="refs"><a href="dx-ball.md">The DX-Ball story</a></p>
</div>

<div class="finding">
<h3>It can read a program and say what it does.</h3>
<p>Shown only the bytes, with no names and no code, Sonnet predicted the answer for 544 of 556 files, including real files found on the web. That helps whenever you have a program but not its code: old software, like the DX-Ball game, or a file you want to understand before you run it.</p>
<p class="refs"><a href="#reading-and-writing-at-scale">Reading and writing at scale</a></p>
</div>

<div class="finding">
<h3>Most reading mistakes were about format, not understanding.</h3>
<p>8 of the 9 misses on real files had the right number, but in bold, like <code>**11**</code>, and one of those also had an explanation after it. The checker wants the number alone, so it counts these as wrong. If another program reads the reply, the exact format matters.</p>
<p class="refs"><a href="#reading-and-writing-at-scale">The details</a></p>
</div>

<div class="finding">
<h3>Faced with a hard calculation, it chose not to guess.</h3>
<p>For a hash function that repeats its work 100 times, Sonnet tried to work out the answer by hand for a long time, about 400,000 tokens, then said it couldn't give a number it trusted without running the code. That one question cost about $4, nearly half of the whole run.</p>
<p class="refs"><a href="#reading-and-writing-at-scale">The details</a></p>
</div>

<div class="finding">
<h3>Harder problems are where writing breaks.</h3>
<p>Programs for a single operation almost always worked. Contest problems need loops and arithmetic: Sonnet solved all 4 of the easier ones, 2 of the 6 harder ones, and 1 of the 2 without a rating. Two replies weren't valid files at all, because the file ends before a part it announces: a classic mistake when writing a file by hand.</p>
<p class="refs"><a href="#reading-and-writing-at-scale">The details</a></p>
</div>

<div class="finding">
<h3>A smaller model can catch up with a little help.</h3>
<p>On its own, Inkling 2 Mini picked wrong bytes and its files weren't valid. With a one-page list of the byte for each operation, it wrote a correct digit-adding program. One extra paragraph about iPhone sound took its demo page from 12 to 13 of 13 checks.</p>
<p class="refs"><a href="#helping-a-smaller-model">The guided prompts</a> · <a href="#writing-the-demo-web-page">The demo pages</a></p>
</div>

<div class="finding">
<h3>It's cheap to run and quick to check.</h3>
<p>The 599 questions took about 40 minutes and cost about $8.45 at list prices. Building the questions takes seconds, and checking the replies takes from under a second to a few minutes. Every reply is saved, so anyone can check the results again without asking a model.</p>
<p class="refs"><a href="datasets.md#how-it-scales">How it scales</a></p>
</div>

</div>

## What the numbers don't tell you

These results come mostly from Claude models, with one attempt per question. They show what happened on these questions, not how often a model gets it right in general. The same task can come out differently on a second try: the program for the bitwise AND operation passed in the sample and failed in the full run. A pass also covers only the inputs the checker tried, not every possible input. [How the trials were run](#how-the-trials-were-run-and-what-a-pass-means)

## Deciding whether to retry

Opus and Sonnet each wrote a working `retry` program on the first try, and each changed it correctly when asked. Haiku's program ran, but gave the right answer for only 2 of the 528 inputs.

On 23 November 2026, three Claude models got the same prompt. It asks for a Wasm file with one function, `retry`, that answers 1 for the server error code 429 and for 500 to 599, and 0 for any other number. The two models that passed then got their own bytes back with a change request: also try again on 408, and stop on 501. [The prompt](../prompts/write.txt) · [The change request sent to Sonnet](../trials/revise/claude-sonnet-5-5-1/prompt.txt)

| Model | First program | The change |
| --- | --- | --- |
| Claude Opus 5.5 | 528 of 528 answers right | Only 408 and 501 changed, as asked |
| Claude Sonnet 5.5 | 528 of 528 answers right | Only 408 and 501 changed, as asked |
| Claude Haiku 5.5 | 2 of 528 answers right | Not tried: no passing program to change |

Opus and Sonnet each sent a working 54-byte file. Haiku's file ran, but it compared numbers the wrong way, as if they could never be negative. For example, it answered 1 for 404 and 0 for 500. [Opus's reply](../trials/write/claude-opus-5-5-1/reply.txt) · [Sonnet's reply](../trials/write/claude-sonnet-5-5-1/reply.txt) · [Haiku's reply](../trials/write/claude-haiku-5-5-1/reply.txt)

## Adding up a number's digits

All three Claude models wrote a working `digit_sum`, right on all 1,353 inputs. That includes Haiku, which had missed `retry`. With one attempt each, that difference says little about either model.

`digit_sum` adds up the digits of a number: 407 gives 11. For a negative number, it ignores the minus sign, so −2147483648, the smallest number Wasm stores in 32 bits, gives 47. A correct program needs a loop, a running total and division. On 23 November 2026, the same three models each got one prompt for it. The checker tries 1,353 numbers: every number from 0 to 1,000 and from −1 to −100, each power of ten and its neighbours, the 32-bit limits, and 200 numbers spread over the whole range. [The prompt](../prompts/digits.txt) · [Inputs and expected answers](../src/wb_task.erl)

| Model | File size | Answers |
| --- | --- | --- |
| Claude Opus 5.5 | 90 bytes | 1,353 of 1,353 right |
| Claude Sonnet 5.5 | 90 bytes | 1,353 of 1,353 right |
| Claude Haiku 5.5 | 95 bytes | 1,353 of 1,353 right |

All three programs work the same way: make the number positive, then repeatedly take its last digit and add it to the total. Opus and Sonnet sent the same 90 bytes. Haiku's used one more variable. None of the three matches the example program under `examples/digits/`, which Claude Opus wrote while the checker was being built. [Opus's reply](../trials/digits/claude-opus-5-5-1/reply.txt) · [Sonnet's reply](../trials/digits/claude-sonnet-5-5-1/reply.txt) · [Haiku's reply](../trials/digits/claude-haiku-5-5-1/reply.txt)

## Placing a game sound left or right

All three Claude models wrote a working `screen_pan`, right at all 641 screen positions. Each then swapped the sound's left and right on request, changing exactly the 640 answers that should change.

`screen_pan` comes from the 1996 game DX-Ball. Given where the ball is on screen, it says how far left or right to play the sound. The REA team recovered this rule from the game's machine code and published it. On 23 November 2026, each model got one prompt describing the rule, then its own bytes back with a request to swap left and right. Each cell is one attempt, checked at every position from 0 to 640. [How the demo was made](dx-ball.md)

| Model | First program | The swap |
| --- | --- | --- |
| Claude Sonnet 5.5 | 641 of 641 right | 641 of 641 right, only the 640 requested changes |
| Claude Opus 5.5 | 641 of 641 right | 641 of 641 right, only the 640 requested changes |
| Claude Haiku 5.5 | 641 of 641 right | 641 of 641 right, only the 640 requested changes |

All three first replies are the same 76 bytes. They match the example program under `examples/pan/`, which Claude Opus wrote while the checker was being built. Sonnet and Opus swapped the sound by changing one byte, and Haiku by changing two. All six files gave the same answers in Wasmtime, a second program that runs Wasm files. [First replies](../trials/pan/) · [Swapped replies](../trials/reverse/)

These checks test the rule REA published, not the original game. REA's own tests against the game, 3,205 cases run in an emulator of the game's processor, are REA's work and weren't repeated here, because the game's program file wasn't available. [REA's checks and ours](dx-ball-evidence.md#which-cases-can-be-checked)

## Writing the demo web page

Every demo page the models wrote passed all 13 browser checks, except the local model's first page. That one passed 12, because it never asked an iPhone to allow sound. With a guided prompt, its next page passed all 13.

The models wrote the whole DX-Ball demo page as one HTML file, in two rounds. A program drove each page in Chrome, first with the recorded sound programs and then with stand-ins, to confirm that the page really uses the model's Wasm and doesn't work out the sound itself. [How a page is checked](ui.md)

In the first round, on 23 November 2026, the prompt said what the page does, not how it looks. In the second round, on 24 November, the prompt also described how the hand-written demo looks. All four pages in that round passed all 13 checks, and all four look close to the demo as it looked then, before it moved to the site’s colors. The checks don't compare looks, so that was judged by eye. [The second round](ui.md#with-the-look-described) · [The prompt](../prompts/ui.txt)

<details>
<summary>Both rounds: page size and result, per model</summary>

| Round | Model | Page | Result |
| --- | --- | --- | --- |
| First | Claude Sonnet 5.5 | 8,138 bytes | all 13 checks pass |
| First | Claude Opus 5.5 | 15,242 bytes | all 13 checks pass |
| First | Claude Haiku 5.5 | 7,456 bytes | all 13 checks pass |
| First | Inkling 2 Mini | 9,403 bytes | 12 of 13: never asks an iPhone to allow sound |
| First | Inkling 2 Mini, with a guide | 12,702 bytes | all 13 checks pass |
| Second | Claude Sonnet 5.5 | 10,890 bytes | all 13 checks pass |
| Second | Claude Opus 5.5 | 20,556 bytes | all 13 checks pass |
| Second | Claude Haiku 5.5 | 12,804 bytes | all 13 checks pass |
| Second | Inkling 2 Mini, with a guide | 14,886 bytes | all 13 checks pass |

</details>

Some limits to keep in mind:

- The checks record what each page asks the browser to play, not what reaches a speaker. The maintainer heard the sound on an iPhone on 24 November, but didn't record which pages or which iOS version.
- Haiku's page asks for sound only through a feature of recent Safari. The check imitates that feature, so it doesn't cover older iPhones.
- The local model's guided prompt adds one paragraph that names the feature to use. Its pass shows that the model follows that paragraph. One attempt can't separate the paragraph's effect from chance.
- Sonnet's second-round page first failed because of a timing flaw in one check. The check now times itself from the click, and the unchanged page passes. [All the pages](../trials/ui/)

## Helping a smaller model

On its own, the local model Inkling 2 Mini couldn't write a valid file. With a one-page guide added to the prompt, it wrote a `digit_sum` that was right on all 1,353 inputs, and a `retry` that was right on 520 of 528. The three Claude models passed with the guided prompts too.

On 23 November 2026, Inkling 2 Mini (`inkling-2-mini:26b-a5b-nvfp4`, run through Ollama on a Mac) got both plain prompts, then both guided prompts. The guided prompt keeps the task and adds a reference card: how the file is laid out, how numbers are written, and the byte for each operation and the order of its inputs. It also asks for the work in numbered steps. [Guided retry prompt](../prompts/write.guided.txt) · [Guided digit_sum prompt](../prompts/digits.guided.txt)

<details>
<summary>The results, per model and prompt</summary>

Each cell is one attempt.

| Model | `retry`, plain | `retry`, guided | `digit_sum`, plain | `digit_sum`, guided |
| --- | --- | --- | --- | --- |
| Inkling 2 Mini | not a valid file | 520 of 528 | not a valid file | 1,353 of 1,353 |
| Claude Haiku 5.5 | 2 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Sonnet 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |
| Claude Opus 5.5 | 528 of 528 | 528 of 528 | 1,353 of 1,353 | 1,353 of 1,353 |

</details>

**What went wrong without the guide.** The local model laid out every part of the file, and every length, correctly. It picked the wrong bytes for some operations. In `retry`, it wrote `45` (test for zero) where `46` (test for equal) belongs and turned the range test around, so the file failed the Wasm rules. In `digit_sum`, it used `06`, which isn't an operation at all. [Plain retry](../trials/write/inkling-2-mini-1/) · [Plain digit_sum](../trials/digits/inkling-2-mini-1/)

**What the guide changed.** With the guide, its `digit_sum` passed, in erlang_wasm and in Wasmtime. Its `retry` ran, but it wrote 500 as `ec 03`, which means 492, so it also says try again for 492 to 499. The guided attempts took 7 and 10 minutes, against 10 and 40 for the plain ones. [Guided retry](../trials/write/inkling-2-mini-guided-1/) · [Guided digit_sum](../trials/digits/inkling-2-mini-guided-1/)

Opus and Sonnet sent the same bytes with both prompts. Haiku's guided `retry` passed where its first attempt hadn't. With one attempt each, these results can't separate the effect of the guide from chance. Each local trial keeps the model's thinking in `thinking.txt`.

The local model also got the guided prompt for the game sound once. Its 74-byte file isn't valid. One part of the file is missing the count that should open it, so the reader takes the next byte, `60`, to mean 96 entries. The number 1.0 is also one byte short. It wrote 1.5625 and 500.0 correctly, and its steps match the other models'. With no working file, it couldn't be asked for the left-right swap, so no demo runs on its work alone yet. [Guided sound prompt](../prompts/pan.guided.txt) · [Its reply](../trials/pan/inkling-2-mini-guided-1/reply.txt)

## Reading and writing at scale

On 24 November 2026, Claude Sonnet 5.5 answered two new kinds of question from public collections. Either it read a Wasm file and said what it returns, or it wrote a working file from a description or a contest problem. The right answers come from the collections, not from us. Sonnet answered a sample of 33 first, then all 599 usable questions, one attempt each. [What was asked, and how it scales](datasets.md)

| Question | Sample | Full run |
| --- | --- | --- |
| Read a small test program, predict the answer | 12 of 12 right | 361 of 364 right |
| Write a program for one operation | 8 of 8 passed | 30 of 31 passed |
| Read a real file from the web, predict the answer | 8 of 8 right | 183 of 192 right |
| Write a program for a contest problem | 1 of 5 passed | 7 of 12 passed |

What the numbers mean:

- **Reading small programs is close to solved for this model.** The 3 misses involve unusual bit patterns, such as `0xf0f0f0f0`, run through the AND and XOR operations.
- **On real files, format mattered as much as reasoning.** 8 of the 9 misses had the right number, but in bold, and one of those also had an explanation. The checker accepts the number alone, just as it accepts nothing but the bytes for a program. The ninth miss is the hash function, where Sonnet gave no number.
- **One attempt isn't the whole story.** The program for the AND operation passed in the sample and failed in the full run. The contest problem Rubik's Cube Coloring went the other way.
- **Contest problems are the real test.** Sonnet solved all 4 problems rated 7 to 9 on the collection's scale, 2 of the 6 rated 10 to 12, and 1 of the 2 without a rating. One failure comes from the collection, not the model: a test uses −27 for a problem that only allows 1 to 32.

<details>
<summary>Where the questions came from, how the sample was drawn, and what the run cost</summary>

| Source | Looked at | Usable | Left out, and why |
| --- | --- | --- | --- |
| WebAssembly test suite | 374 tests in `i32.wast` at testsuite `92a3d80` | 364 reading, 31 writing | 10 tests expect the call to fail, so there is no number to predict |
| WasmBench | 8,461 files in the v1.0 filtered release | 192 | 7,612 larger than 2,048 bytes; 540 that need functions from outside; 99 without a function that takes up to two whole numbers; 17 with no call that returned; 1 that can't be started |
| CodeContests | 624 problems in the valid, test, and first training files at revision `802411c` | 12 | 594 whose input isn't one or two whole numbers; 12 whose output isn't one whole number; 5 with a value too big for 32 bits; 1 whose tests disagree |

Each sample takes the usable questions in a fixed shuffled order: the SHA-256 of `"2026:<id>"`. The WasmBench sample only uses files from openly licensed projects, and the test-suite sample always includes the addition example. The full run used every usable question. Its replies are in `trials/corpus/`, and its questions are rebuilt from the pinned sources.

The full run took about 40 minutes, with the three sources running side by side. It used 621,920 input and 690,551 output tokens, about $8.45 at list prices, $4.02 of it for the hash function alone. One WasmBench question was asked twice, where two workers met, and its record says so. [Full run summary](../trials/corpus/summary.config)

Replay any total with `bin/wasm-bytes batch TRACK LABEL`. The sample uses the label `claude-sonnet-5-5-1`. The full run uses `claude-sonnet-5-5-corpus-1`, with `--cases _build/cases --replies trials/corpus` after rebuilding its questions.

</details>

## The same file in another program

Sonnet's `retry` file and all three `digit_sum` files gave the right answer on every input (528 and 1,353) in two different programs that run Wasm: erlang_wasm and Wasmtime. This held on three setups of one Apple silicon Mac: macOS, Linux, and Linux imitating an Intel-style x86_64 processor. A run on separate x86_64 hardware hasn't been recorded yet. [Commands, records and limits](evidence.md)

<details>
<summary>Program versions and the result on each setup</summary>

On 23 November 2026, Sonnet's `retry` file ran in erlang_wasm 0.11.0 and in Wasmtime 50.0.1 on all 528 inputs. Both gave the right answer every time and reported the same SHA-256 fingerprint for the bytes they received.

| Setup | erlang_wasm | Wasmtime |
| --- | --- | --- |
| macOS 27.2, arm64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, aarch64 | 528 of 528 | 528 of 528 |
| Debian 13 in a container, x86_64 emulated | 528 of 528 | 528 of 528 |

The three `digit_sum` files gave the same result: 1,353 of 1,353 in both programs on the same three setups.

</details>

## How the trials were run, and what a pass means

Each result is one attempt at one small task. A pass means the file had the requested shape and gave the expected answer on every input the checker tried. It doesn't prove the file is right for every possible input. [How the checker works](runner.md)

The tables count only attempts with a saved prompt, an unedited reply and the model's name. The 14 examples under `examples/` were written to show how the checker behaves, and aren't counted. One of them, the passing `retry` example, came from the same Opus model while the checker was being built. The recorded Opus and Sonnet replies decode to exactly the same bytes. Both trials ran without tools, so neither copied the example, but the example isn't independent of the Opus trial. [Trial records](../trials/) · [Passing example](../examples/write/accepted/reply.txt)

<details>
<summary>How the trials were run</summary>

The Claude trials used Claude Code with tools turned off, default settings, and a replacement system prompt. Claude Code still added some details about the environment and the account. The local trials used Ollama's chat API on a Mac, with the same system prompt, default settings, and the model's default thinking level.

</details>

## Check the results yourself

Run `bin/wasm-bytes replay` from the project folder for the short version, or `bin/wasm-bytes demo` to replay every example and trial. To try another model, send it the same prompt and keep its reply exactly as it came. [Try it yourself](try.md) · [How to record a trial](../trials/README.md)

Next, we plan larger tasks, repeated attempts with other AI providers, and asking for only the function's instructions, or for Wasm's text format (WAT), instead of the whole file.
