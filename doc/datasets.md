# Reading and writing WebAssembly

The rest of this project asks a model to write small programs from descriptions we wrote ourselves. This page turns the question around and widens it. Can a model look at a compiled WebAssembly program and say what it will return? Can it write a working program for a problem it has never seen, taken from a public collection? Every right answer here comes from that collection, never from us. Start with the simplest example, 32-bit addition. [One example of each](#one-example-of-each)

## What the model is asked

**Reading.** We show the model a whole WebAssembly file, written out as hex: two characters for each byte. Then we ask one question, such as "What signed integer does `f(2147483647, 1)` return?" The prompt doesn't name the operation, show any source code, or hint at the answer. The model must reply with just the number. A sentence around the right number doesn't count, as prose around a program doesn't count anywhere else in this project.

**Writing.** We give the model a signature and a short description in English, or a programming contest problem. It replies with a complete WebAssembly file as hex. We run that file, unchanged, on test cases the prompt never showed, and compare every answer with the expected one. Any program that gets them all right passes, however it is written.

<div class="flow-pair">
<div>
<h3>Reading</h3>
<ol class="flow">
<li>
<div class="card">
<p class="what"><strong>The collection gives a call and its answer.</strong> A test from the WebAssembly test suite, or what a real file returned when we ran it.</p>
<p class="out"><code>f(2147483647, 1)</code> returns <code>-2147483648</code></p>
</div>
</li>
<li>
<p class="via">The file's bytes and one question, never the answer</p>
<div class="card">
<p class="what"><strong>The model replies with one number.</strong> It sees only the bytes. No name, no source code.</p>
<p class="out"><code>-2147483648</code></p>
</div>
</li>
<li>
<p class="via">The reply, as it came back</p>
<div class="card">
<p class="what"><strong>We compare it with the answer.</strong> Right, wrong, or not a number.</p>
<p class="out"><code>pass</code>, <code>wrong_answer</code> or <code>malformed_answer</code></p>
</div>
</li>
</ol>
</div>
<div>
<h3>Writing</h3>
<ol class="flow">
<li>
<div class="card">
<p class="what"><strong>The collection gives tests and their answers.</strong> The test suite's checks for one instruction, or a contest problem's hidden tests.</p>
<p class="out">8 tests for addition, overflow included</p>
</div>
</li>
<li>
<p class="via">A signature and a description, never the tests</p>
<div class="card">
<p class="what"><strong>The model writes every byte.</strong> Nothing is added to its reply, and nothing is fixed.</p>
<p class="out"><code>00 61 73 6d 01 00 00 00 …</code> 39 bytes</p>
</div>
</li>
<li>
<p class="via">The bytes, unchanged</p>
<div class="card">
<p class="what"><strong>We run it on every test.</strong> Each call starts fresh, with a limit on work and time.</p>
<p class="out"><code>8 of 8 right</code>: <code>pass</code></p>
</div>
</li>
</ol>
</div>
</div>

## One example of each

Both examples use the same fact from the official WebAssembly tests. Wasm stores these numbers in 32 bits, so the largest is 2147483647. Add 1 to it and the result wraps around to the smallest, −2147483648.

### Read the bytes, predict the answer

This is everything the model sees. Nothing in it names the operation, shows the code, or gives the answer. [The prompt as sent](../trials/cases/spec/read/add-41/claude-sonnet-5-5-1/prompt.txt)

```text
Here is a complete WebAssembly module, as hex: two hexadecimal digits for each byte.

00 61 73 6d 01 00 00 00 01 07 01 60 02 7f 7f 01
7f 03 02 01 00 07 05 01 01 66 00 00 0a 09 01 07
00 20 00 20 01 6a 0b

What signed integer does f(2147483647, 1) return? Reply with just the number.
```

The file's function, `f`, adds its two numbers. Sonnet replied with just `-2147483648`. To check that reply yourself:

```sh
bin/wasm-bytes check case spec/read/add-41 trials/cases/spec/read/add-41/claude-sonnet-5-5-1/reply.txt
```

```text
  call     f(2147483647, 1)
  answer   -2147483648
  expected -2147483648
  verdict  pass
```

`pass` means the reply is exactly the right number. A reply of `2147483648`, the same bits read as a number that can't be negative, gets `wrong_answer`. A sentence around the right number gets `malformed_answer`, because the checker accepts the number alone and nothing else. [Both failing examples](../examples/cases/spec/read/add-41/)

### Write bytes that pass the tests

The model gets one sentence, followed by the same formatting rules as every writing task: "Write a complete WebAssembly module that exports f(i32, i32) -> i32. It adds its two arguments, wrapping on 32-bit overflow. Reply with the complete file as hex." Sonnet sent back 39 bytes. To check them yourself:

```sh
bin/wasm-bytes check case spec/write/add trials/cases/spec/write/add/claude-sonnet-5-5-1/reply.txt
```

```text
  hex      39 bytes
  wasm     decodes and validates (erlang_wasm 0.11.0)
  profile  exports f : (i32, i32) -> (i32); no imports
  calls    8 inputs, each in a fresh instance; fuel 10000 and a 1000 ms deadline per call
  answers  8 of 8 match the reference
  verdict  pass
```

erlang_wasm confirmed that the file follows the rules of Wasm. Then the checker called `f` with the 8 pairs of numbers the official tests use for addition, including the one that wraps around. `pass` means every call gave the expected answer. Any file that does so passes, however its bytes are written. These 39 bytes happen to be the same as the file in the reading example, although the model never saw that file. [The prompt as sent](../trials/cases/spec/write/add/claude-sonnet-5-5-1/prompt.txt) · [The unedited reply](../trials/cases/spec/write/add/claude-sonnet-5-5-1/reply.txt)

A file can follow every rule and still give wrong answers. This example reply is the same file with one byte changed: `6a` (add) became `6b` (subtract). It still runs, and the check shows you the first numbers where it goes wrong.

```sh
bin/wasm-bytes check case spec/write/add examples/cases/spec/write/add/subtracts/reply.txt
```

```text
  wrong    6 answers differ from the reference
  first    input (1, 1): expected 2, got 0
  answers  2 of 8 match the reference
  verdict  wrong_answer
```

## Where the questions come from

**The WebAssembly test suite.** These are the tests the people who write the WebAssembly standard use to check that engines agree with each other. Each one says, for example, "calling `i32.add` with 2147483647 and 1 must give −2147483648". We use the file for 32-bit integer arithmetic, comparisons, and bit operations. For a reading question, we build a tiny program that runs one instruction and ask about one test. For a writing task, we describe the instruction in a sentence, and every test for it becomes a check.

**WasmBench.** A research collection of 8,461 WebAssembly files found on real websites, GitHub, npm, and elsewhere. We keep the files small enough to show in a prompt and that run on their own, and ask what one of their functions returns. Nobody wrote down the answers, so we run each file ourselves and record what it returns. We only use a call that returns the same value every time.

**CodeContests.** A collection of programming contest problems published by DeepMind, with the inputs and outputs the contest used for grading. We keep the problems whose input is one or two numbers and whose output is one number, so a solution can be a function `f(a, b)`. The model sees the problem statement, including its worked examples. It is graded on the hidden tests, which the prompt never shows.

## What happened

We sent the questions to Claude Sonnet 5.5, one attempt each, in two rounds on 24 November 2026. First a small sample of 33 questions, then every usable question from the three sources: 599.

| Question | Sample | Full run |
| --- | --- | --- |
| Reading the test suite's programs | 12 of 12 right | 361 of 364 right |
| Writing a program for a test-suite instruction | 8 of 8 passed | 30 of 31 passed |
| Reading real files from WasmBench | 8 of 8 right | 183 of 192 right |
| Writing a program for a contest problem | 1 of 5 passed | 7 of 12 passed |

**Reading the test suite's programs was nearly perfect.** The three misses involve unusual bit patterns. Two are calls whose arguments mix ones and zeros in blocks, such as `0xf0f0f0f0`, through `and` and `xor`. The third is a sign extension.

**Reading real files went almost as well, with one catch.** Sonnet gave the right number, and nothing else, for 183 of the 192 files. Seven more replies had the right number, but in bold Markdown, such as `**11**`, and one had the right number followed by an explanation. The checker accepts only a bare number, so those count as malformed. The last miss is `testhash`, a hash function that loops 100 times. Sonnet reasoned for about 400,000 tokens, then said it couldn't give a trustworthy number without running the code.

**Writing a single instruction was easy, and a contest problem was hard.** 30 of the 31 instruction programs passed. The one miss, bitwise AND, had passed in the sample run, so the same task can go either way from one attempt to the next. 7 of the 12 contest problems passed: every problem rated 7 to 9 on the dataset's scale, 2 of the 6 rated 10 to 12, and one of the two unrated AtCoder problems. Of the 5 failures, 2 replies are not valid WebAssembly, because the file ends before a section it declares. One fails validation, one is too slow on a large input, and one crashes on the input −27. That last problem only allows inputs from 1 to 32, but some of the dataset's generated tests go outside a problem's own limits.

These numbers describe one model and one attempt per question. They tell you what happened on these questions, not how often a model succeeds in general. [All results](status.md#reading-and-writing-at-scale)

## How it scales

The same commands handle one question, a sample, or a whole collection. What changes is how many questions you send and how long you wait for the model.

| Source | In the collection | Usable | Sample | Full run |
| --- | --- | --- | --- | --- |
| WebAssembly test suite | 374 tests | 364 reading, 31 writing | 20 | 395 |
| WasmBench | 8,461 files | 192 | 8 | 192 |
| CodeContests | 624 problems in the 3 files we fetched | 12 | 5 | 12 |

Most of the collections drop out before anything reaches the model. Most WasmBench files are larger than 2 KB, which is too long to show in a prompt as hex, and many expect a host to provide functions they import. Most contest problems read more than two numbers, or read text. The 38 contest files we haven't fetched hold about 13,000 more problems, and a run over them works the same way.

**What the full run took.** About 40 minutes, with the three sources running side by side: 23 minutes for the test suite's 395 questions, 14 for the 12 contest problems, and 40 for WasmBench's 192 files, 30 of them on one question. It used 621,920 input tokens and 690,551 output tokens, about $8.45 at Sonnet 5.5's list prices. Nearly half of that went to `testhash` alone. Without it, the run would have cost about $4.43.

**The runner's own work is small next to the model's.** Building every question takes seconds: under a second for the test suite, and about 2 seconds to look at all 8,461 WasmBench files. Checking all 395 test-suite replies takes under a second. Checking the contest programs takes about 3.5 minutes, because each one runs on its hidden tests, 1,898 in all, and the slow ones wait out their 5-second limit.

## Check a question yourself

Each question has an id, such as `spec/read/add-41`. List them, print the exact prompt for one, then check a saved reply:

```sh
bin/wasm-bytes cases spec
bin/wasm-bytes prompt case spec/read/add-41
bin/wasm-bytes check case spec/read/add-41 trials/cases/spec/read/add-41/claude-sonnet-5-5-1/reply.txt
```

For a reading question, `pass` means the reply is exactly the right number. `wrong_answer` means it is a different number. `malformed_answer` means the reply isn't one number, for example a sentence around it. `too_large` means it is longer than 1,024 bytes.

For a writing task, the check works as it does for every program in this project. It reads the hex, has erlang_wasm validate the program, then runs every test, each in a fresh instance. A failing check names one test with the expected and actual answer. [Every verdict](runner.md)

To run the same bytes in Wasmtime as well, a second WebAssembly engine:

```sh
bin/wasm-bytes compare case spec/write/add trials/cases/spec/write/add/claude-sonnet-5-5-1/reply.txt
```

Each call gets 10,000 units of work and one second, as everywhere else in this project. Contest problems get more, 200,000,000 units and five seconds, because a contest solution loops over its input.

## Replay a whole batch

A batch is every question from one source, with the replies saved under one label. The summary counts what was answered, keeps unanswered questions apart, and names one failing test for each failure:

```sh
bin/wasm-bytes batch spec claude-sonnet-5-5-1
bin/wasm-bytes batch wasmbench claude-sonnet-5-5-1
bin/wasm-bytes batch codecontests claude-sonnet-5-5-1
```

For reading, it counts right answers out of the questions answered. For writing, it counts how many replies were valid programs and how many passed every test. A valid program is one erlang_wasm accepts, whatever it then returns. The first lines repeat where the questions came from: how many items were looked at, how many could become questions, and why the others were left out.

The full run's replies are in `trials/corpus/`. Its questions aren't kept in the repository, because some WasmBench files aren't openly licensed. Rebuild them from the pinned sources, as the next section shows, then replay the full run:

```sh
bin/wasm-bytes batch wasmbench claude-sonnet-5-5-corpus-1 --cases _build/cases --replies trials/corpus
```

## Build the questions from the sources

Every source is pinned to an exact version, and the selection is repeatable. Questions are taken in the order of the SHA-256 of `"<seed>:<id>"`, with seed 2026, so anyone can recompute the order. Each question records where in its source it came from, and each source's `selection.config` records what was looked at and why items were left out.

**The test suite.** Its file is in the repository, and the build checks its hash before using it. This rewrites the 20-question sample in `cases/`, byte for byte:

```sh
bin/wasm-bytes prepare spec --read 12 --write 8 --seed 2026 --out cases
```

Without `--read`, `--write` and `--out`, it builds every question under `_build/cases/`: 364 reading questions and 31 writing tasks. The other 10 tests expect the call to fail, so there is no number to predict.

**WasmBench.** The files come in a 1.14 GB archive, 5.5 GB once unpacked. This downloads it, checks its hash, unpacks it, and builds every usable question under `_build/cases/`. It needs curl and 7-Zip.

```sh
scripts/fetch-wasmbench.sh
bin/wasm-bytes prepare wasmbench --from _build/datasets/wasmbench/extracted
```

The files aren't ours. WasmBench's authors share them for research and claim no ownership. So the sample in the repository only uses files from projects whose license GitHub reports as open. To rebuild it, look up those licenses, then build the sample:

```sh
scripts/wasmbench-licenses.sh _build/cases
bin/wasm-bytes prepare wasmbench --from _build/datasets/wasmbench/extracted \
    --sample 8 --licenses datasets/wasmbench/licenses.config --out cases
```

A real file can keep its function names inside it, and the prompt shows the whole file. So a question about a function called `add` may give a hint that a test-suite question doesn't.

**CodeContests.** This downloads the three files the questions came from, checks each against the hash the dataset records, and picks out the problems that fit. It needs Python 3, and installs pyarrow in `_build/venv` the first time.

```sh
scripts/fetch-codecontests.sh
bin/wasm-bytes prepare codecontests --from _build/datasets/code_contests/candidates.jsonl
```

Each test becomes one call. Its input numbers are the arguments, in order, and its output is the expected answer: the input `4 2` with the output `7` becomes `f(4, 2)`, expected to return 7. A problem is left out when a number doesn't fit in 32 bits, or when two tests disagree about the same input. To look further, name more of the dataset's training files, for example `scripts/fetch-codecontests.sh train-00001-of-00039-e092fe56fda18715.parquet`. The file names are on the [dataset page](https://huggingface.co/datasets/deepmind/code_contests/tree/main/data). The dataset is published under CC BY 4.0.

## Ask a model yourself

With the Claude Code CLI signed in, this sends every question from one source to a model and saves each reply under `trials/cases/<id>/<label>/`, with the prompt and the verdict:

```sh
scripts/record-claude-cases.sh spec my-label claude-sonnet-5-5
bin/wasm-bytes batch spec my-label
```

It skips questions that already have a reply, so you can restart it after an interruption. For a full run, point it at the questions you built and choose where the replies go:

```sh
CASES=_build/cases REPLIES=_build/corpus/replies scripts/record-claude-cases.sh wasmbench my-label claude-sonnet-5-5
bin/wasm-bytes batch wasmbench my-label --cases _build/cases --replies _build/corpus/replies
```

[Recording trials](../trials/README.md)
