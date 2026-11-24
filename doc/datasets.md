# Reading and writing tracks

The reading and writing tracks measure two things over public datasets. Can a model read WebAssembly bytes and predict what a function returns? Can it take an English description and write a complete `.wasm` file that does the job? Read this page to list and check cases, replay a batch of saved replies, prepare a track from its pinned source, and run a larger corpus. The README walks through one case in each direction. [The addition example](../README.md#reading-and-writing-32-bit-addition)

## Results so far

On 24 November 2026, Claude Sonnet 5.5 answered a sample from each source, one attempt per case. Each number says what was tested. [Details and caveats](status.md#reading-and-writing-tracks)

| Track | What was asked | Result |
| --- | --- | --- |
| Spec tests, reading | 12 calls to one-instruction modules built from `i32.wast` | 12 of 12 predictions correct |
| Spec tests, writing | 8 instructions described in English, each checked on its 7 to 17 upstream assertions | 8 of 8 valid modules, 8 of 8 passed every check |
| WasmBench, reading | 8 calls to real binaries of 74 to 751 bytes, from openly licensed projects | 8 of 8 predictions correct |
| CodeContests, writing | 5 problems, each checked on its 58 to 248 private and generated tests | 3 of 5 valid modules, 1 of 5 passed every check |

These come from one model and one attempt per case, on small modules and a small sample. They say what happened on these cases, not how often a model succeeds.

## How a case is checked

<div class="flow-pair">
<div>
<h3>Reading</h3>
<ol class="flow">
<li>
<div class="card">
<p class="what"><strong>The source gives a call and its answer.</strong> An upstream spec assertion, or what a WasmBench binary returned when the runner called it.</p>
<p class="out"><code>f(2147483647, 1)</code> returns <code>-2147483648</code></p>
</div>
</li>
<li>
<p class="via">The module's bytes and one question, never the answer</p>
<div class="card">
<p class="what"><strong>The model replies with one number.</strong> It sees the module as hex. The prompt has no operation name and no source code.</p>
<p class="out"><code>-2147483648</code></p>
</div>
</li>
<li>
<p class="via">The reply, unchanged</p>
<div class="card">
<p class="what"><strong>The runner compares it with the answer.</strong> A sentence around the right number is not an answer.</p>
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
<p class="what"><strong>The source gives calls and their answers.</strong> The upstream assertions for one instruction, or a contest problem's private and generated tests.</p>
<p class="out">8 assertions for <code>i32.add</code>, overflow included</p>
</div>
</li>
<li>
<p class="via">A signature and a description, never the calls</p>
<div class="card">
<p class="what"><strong>The model writes every byte, as hex.</strong> Nothing is added to its reply, and no length is corrected.</p>
<p class="out"><code>00 61 73 6d 01 00 00 00 …</code> 39 bytes</p>
</div>
</li>
<li>
<p class="via">The bytes, unchanged</p>
<div class="card">
<p class="what"><strong>erlang_wasm validates the module, and the runner calls it.</strong> Each call runs in a fresh instance, under fuel and a deadline.</p>
<p class="out"><code>8 of 8 match</code>: <code>pass</code></p>
</div>
</li>
</ol>
</div>
</div>

## Cases and tracks

A case is one question for a model. A reading case shows a module's bytes as hex and asks what one call returns. A writing case gives a signature and a description, and checks the module the model sends back on recorded calls. Every expected answer comes from the source, never from this project's own code.

| Track | Direction | Source | Expected answers |
| --- | --- | --- | --- |
| `spec` | read and write | [WebAssembly/testsuite](https://github.com/WebAssembly/testsuite) at `92a3d80`, `i32.wast` | The upstream `assert_return` assertions |
| `wasmbench` | read | [WasmBench](https://github.com/sola-st/WasmBench) v1.0, filtered binaries | What the binary returned when the runner called it |
| `codecontests` | write | [deepmind/code_contests](https://huggingface.co/datasets/deepmind/code_contests) at revision `802411c` | The dataset's private and generated tests |

The repository keeps a small sample of each track under `cases/`, and the replies one model gave to it under `trials/cases/`. A larger corpus run is opt-in, and writes its cases under `_build/cases/`.

## List, prompt, and check a case

A case id is `TRACK/read/NAME` or `TRACK/write/NAME`. List the cases, print the exact prompt for one, then check a saved reply.

```sh
bin/wasm-bytes cases spec
bin/wasm-bytes prompt case spec/read/add-41
bin/wasm-bytes check case spec/read/add-41 trials/cases/spec/read/add-41/claude-sonnet-5-5-1/reply.txt
```

A reading reply must be one signed decimal integer, with optional whitespace around it. Nothing is extracted from a longer reply, as no hex is extracted from prose.

| Reading verdict | What it means |
| --- | --- |
| `pass` | The number is the expected value. |
| `wrong_answer` | The reply is one number, and not the expected one. |
| `malformed_answer` | The reply is not one integer: for example, a sentence or a code fence around the number. |
| `too_large` | The reply is longer than 1,024 bytes. |

A writing reply is checked like any reply in this project: hex decoding, validation by erlang_wasm, then every recorded call, each in a fresh instance. The interface check asks only for what the prompt asks: an export `f` with the requested signature and no imports. The module may have other functions, a memory, or a start function. Any module that returns every expected value passes, whatever its bytes. The verdicts are the ones in the [verdict guide](runner.md), and a failing check names one input with its expected and actual result. With Wasmtime installed, run the same bytes there too:

```sh
bin/wasm-bytes compare case spec/write/add trials/cases/spec/write/add/claude-sonnet-5-5-1/reply.txt
```

Each call gets 10,000 units of fuel and a one-second deadline, as everywhere else. CodeContests cases are the exception: a contest program loops over its input, so each of their calls gets 200,000,000 units and five seconds. The case records its budget, and the check prints it.

## Replay a batch

A batch is every case of one track, with the reply saved under one label. The summary counts what was attempted, keeps missing replies separate, and names one failing input for each failure.

```sh
bin/wasm-bytes batch spec claude-sonnet-5-5-1
bin/wasm-bytes batch wasmbench claude-sonnet-5-5-1
bin/wasm-bytes batch codecontests claude-sonnet-5-5-1
```

For reading, the summary gives correct predictions out of attempted calls. For writing, it gives how many first replies were valid modules and how many passed every behavioral check, both out of all attempts. A valid module is one erlang_wasm decoded and validated, whatever its calls returned. The `source` lines repeat the track's selection: how many source items were examined, how many could become a case, and why the rest were skipped. [The sample's results](status.md#reading-and-writing-tracks)

## Prepare a track

Each track is built from a pinned source and a seed. The selection takes source items in the order of the SHA-256 of `"<seed>:<id>"`, so you can recompute it without this code. Every track records its upstream ids, examined and skipped counts, and the chosen ids in `selection.config`. Each `case.config` records where in the source its case came from.

### Spec tests

The source file is in the repository, at `datasets/spec/i32.wast`, and the preparation checks its SHA-256 before use. The runner writes each reading module itself, one `local.get` per argument, then the instruction. It keeps an assertion only when that module returns the asserted value. In writing cases, the model supplies every byte.

```sh
bin/wasm-bytes prepare spec --read 12 --write 8 --seed 2026 --out cases
```

That command rewrites the sample in `cases/spec/`, byte for byte. Without `--out`, it writes to `_build/cases/`. Without `--read` and `--write`, it writes every case: 364 reading cases, from the 374 assertions in the first module, and 31 writing cases, one per instruction. The other 10 assertions are traps, which leave no value to predict.

### WasmBench

The binaries are in a 1.14 GB release archive, which unpacks to 5.5 GB. This script downloads the archive, checks its SHA-256, unpacks it, and prints the directory to prepare from. It needs curl and 7-Zip.

```sh
scripts/fetch-wasmbench.sh
bin/wasm-bytes prepare wasmbench --from _build/datasets/wasmbench/extracted
```

The run examines all 8,461 binaries and writes every usable one as a reading case, under `_build/cases/wasmbench/`. A binary is usable when it is at most 2,048 bytes, matches its SHA-256 name, validates in erlang_wasm, imports nothing, and exports a function of up to two `i32` arguments returning one `i32`. The runner calls it with seeded arguments in a fresh instance under the usual limits. The call must return, and return the same value a second time. That value is the expected answer.

The binaries are not this project's: WasmBench's authors redistribute them for research and claim no ownership. The sample in the repository keeps only binaries whose source repository has an open license, as GitHub reports it. `scripts/wasmbench-licenses.sh` writes those licenses to `datasets/wasmbench/licenses.config`. Run it on a corpus run's output, then prepare the sample.

```sh
scripts/wasmbench-licenses.sh _build/cases
bin/wasm-bytes prepare wasmbench --from _build/datasets/wasmbench/extracted \
    --sample 8 --licenses datasets/wasmbench/licenses.config --out cases
```

A real binary can carry its own function names in a name section, and a reading prompt shows the whole binary. So a prompt can name the function it asks about.

### CodeContests

This script downloads parquet files at the pinned revision and checks each one against the SHA-256 the dataset records. It then exports the problems whose every test reads one or two integers and prints one integer. It needs Python 3, and installs pyarrow in `_build/venv` on first use. By default it fetches the three files the sample came from: the valid split (52 MB), the test split (63 MB), and the first of the 39 training files (180 MB).

```sh
scripts/fetch-codecontests.sh
bin/wasm-bytes prepare codecontests --from _build/datasets/code_contests/candidates.jsonl
```

A test becomes a call. Its input integers are the arguments, in order, and its printed integer is the expected return: the input `4 2` with the output `7` becomes `f(4, 2)`, expected to return 7. The prompt shows the problem statement, which contains the public tests as examples. The grading calls are the private and generated tests only, so the prompt shows none of them. A problem is skipped when a value does not fit in 32 bits, or when two tests give different answers for the same input.

For a larger corpus, name more training files, for example `scripts/fetch-codecontests.sh train-00001-of-00039-e092fe56fda18715.parquet`. The file names are on the [dataset page](https://huggingface.co/datasets/deepmind/code_contests/tree/main/data). The dataset is published under CC BY 4.0.

## Record a batch

With an authenticated Claude Code CLI, this script sends every case of a track to a model and saves each reply under `trials/cases/<case id>/<label>/`. It saves the prompt, the reply exactly as received, and `fixture.config` with the verdict.

```sh
scripts/record-claude-cases.sh spec my-label claude-sonnet-5-5
bin/wasm-bytes batch spec my-label
```

The script skips cases that already have a reply, so you can restart an interrupted run. To record a corpus run, set `CASES` to its directory, and pass the same directory to `batch`:

```sh
CASES=_build/cases scripts/record-claude-cases.sh wasmbench my-label claude-sonnet-5-5
bin/wasm-bytes batch wasmbench my-label --cases _build/cases
```

[Recording trials](../trials/README.md)
