# wasm-bytes

wasm-bytes checks WebAssembly binaries that a language model wrote byte by
byte from an English specification. You give a model a prompt, save its
reply, and the runner tells you exactly what happened: the reply was not
hex, the bytes were not a module, the module was invalid, it had the wrong
interface, a call failed, or an answer was wrong, and on which input. The
model writes every byte, including the header and every length; the runner
decodes hex and nothing else. [erlang_wasm](https://github.com/benoitc/erlang_wasm)
decodes, validates and runs the modules. Use it when you want to see how far
a model gets, with any model or chat interface, and no API key.

## Run the demo

You need Erlang/OTP 29 or later and rebar3. The first run fetches
erlang_wasm 0.11.0 from Hex, as pinned in `rebar.lock`.

```sh
bin/wasm-bytes demo
```

The demo replays every saved reply under `examples/` and `trials/`. For
each one it prints where the reply came from, each stage it reached, and its
verdict. It ends with a summary and exits 0 when every verdict is the one the
reply is labelled with.

## Try a model

1. Print the task 1 prompt and give it to the model, as it is:

   ```sh
   bin/wasm-bytes prompt write
   ```

2. Save the reply exactly as you received it, then check it:

   ```sh
   bin/wasm-bytes check write reply.txt
   ```

   To paste instead, give `-` and end the paste with Ctrl-D:

   ```sh
   bin/wasm-bytes check write -
   ```

3. If the verdict is `pass`, print the task 2 prompt for those exact bytes
   and give it to the model:

   ```sh
   bin/wasm-bytes prompt revise --base reply.txt
   ```

   The command refuses a base that does not pass task 1.

4. Save the second reply and check it against the first:

   ```sh
   bin/wasm-bytes check revise revised.txt --base reply.txt
   ```

`check` exits 0 when the reply passes, 1 when it does not, and 2 when the
runner could not judge it (an unreadable file, or a crash in the runner).

## The tasks

**Write.** A module that exports `retry : (i32) -> (i32)`, returning 1 for
429 and for 500 through 599 inclusive, and 0 for every other i32.

**Revise.** The model gets the bytes accepted in task 1 and a change
request: also return 1 for 408, return 0 for 501, keep every other result.
It replies with the complete revised module.

The prompts are files: `prompts/write.txt`, and `prompts/revise.txt` with a
`{{MODULE_HEX}}` line where `prompt revise` puts the base bytes.
`prompts/revise.example.txt` is that prompt rendered for
`examples/write/accepted`. Both prompts ask for hex byte pairs only, with
optional whitespace between pairs. The revise prompt does not restate what
the module does now: the model has to read it from the bytes.

## What the runner checks

Each stage runs only if the one before it passed. The first that fails gives
the verdict.

| stage | verdict when it fails | what failed |
| --- | --- | --- |
| size | `too_large` | the reply is over 64 KiB, or the module over 4096 bytes |
| hex | `malformed_hex` | anything but hex pairs and whitespace between pairs; the line and column are printed |
| wasm | `malformed_wasm` | erlang_wasm cannot decode the bytes (`wasm:compile/1`) |
| wasm | `invalid` | the bytes decode but the module fails validation |
| profile | `interface_mismatch` | not exactly one function exported as `retry : (i32) -> (i32)`, another export, an import, a memory, or a start function |
| calls | `execution_failure` | a call trapped, ran out of fuel, or passed its deadline |
| answers | `wrong_answer` | a result differs from the reference; the input, expected and actual results are printed |

`runner_error` means the runner or erlang_wasm crashed. It is not counted
against the reply.

The profile is checked before anything is instantiated. Each candidate then
runs in a fresh `wasm_instance_worker` with `isolation => fresh`, so no state
survives from one call to the next. Every call has 10,000 fuel and a
1000 ms deadline. A worker killed at a deadline is replaced; after three
deadlines the remaining inputs are reported as not run.

Every candidate is called on 528 inputs: every status from 100 through 599,
the i32 boundaries, values just outside the statuses, negatives of the values
that matter, and values whose low 16 or 31 bits are a value that matters. The
list, and the two reference predicates the results are compared with, are in
`src/wb_task.erl`. The references are written from the specifications,
without looking at any candidate.

For a revision, the runner also checks that the base still passes task 1,
prints a byte diff of the base and the revision (each hunk names the section
of the base it falls in), lists every input whose result changed, and says
whether the changes are exactly the requested ones. A correct revision shows
two: 408 goes from 0 to 1 and 501 goes from 1 to 0.

## The saved replies

`examples/` holds replies written to show each verdict. They were written by
Claude Opus 5.5 in the Claude Code session that built the runner, and checked
with the runner as they were written. None was a clean prompt and reply, so
none counts as a model trial. Each one is labelled with the verdict it is
meant to get, and says what it shows:

| reply | labelled | what it shows |
| --- | --- | --- |
| `write/accepted` | `pass` | a correct 54-byte module |
| `write/prose-around-hex` | `malformed_hex` | the right bytes inside a sentence and a code fence |
| `write/truncated` | `malformed_wasm` | the last byte missing; the runner does not add it |
| `write/stack-mismatch` | `invalid` | well-formed bytes that fail validation |
| `write/wrong-signature` | `interface_mismatch` | `retry` takes an i64 |
| `write/has-memory` | `interface_mismatch` | a memory, exported |
| `write/loops-on-negative` | `execution_failure` | loops forever on negative input; fuel stops it |
| `write/misses-599` | `wrong_answer` | valid, and wrong on one boundary: 599 |
| `revise/accepted` | `pass` | a correct revision of `write/accepted` |
| `revise/stale-lengths` | `malformed_wasm` | new instructions, old section and body lengths |
| `revise/misses-501` | `wrong_answer` | adds 408 and forgets 501 |
| `revise/replaces-429` | `wrong_answer` | a change nobody asked for: 429 goes to 0 |

A fixture is a directory with `reply.txt` (the raw reply) and
`fixture.config` (its provenance, label and note). A valid module also has
`module.wat`, the text it was assembled from; the tests check that the text
and the bytes give the same result on every input.

## The recorded trials

`trials/` holds replies that were sent to a model and recorded, prompt,
reply and model together. These were recorded on 2026-11-23 with
`scripts/record-claude-trial.sh`, one sample each:

| trial | model | verdict | what happened |
| --- | --- | --- | --- |
| `write/claude-opus-5-5-1` | claude-opus-5-5 | `pass` | a correct 54-byte module |
| `write/claude-sonnet-5-5-1` | claude-sonnet-5-5 | `pass` | a correct 54-byte module |
| `write/claude-haiku-5-5-1` | claude-haiku-5-5 | `wrong_answer` | valid, with `i32.ge_u` where `i32.lt_u` belongs: wrong on 526 of 528 inputs |
| `revise/claude-opus-5-5-1` | claude-opus-5-5 | `pass` | revises its own task 1 bytes; 408 and 501 change, nothing else |
| `revise/claude-sonnet-5-5-1` | claude-sonnet-5-5 | `pass` | revises its own task 1 bytes; 408 and 501 change, nothing else |

Read them with these limits in mind:

- One sample per model, with default sampling. A different sample can get
  a different verdict.
- The models ran in Claude Code's headless mode with no tools, no MCP
  servers, no settings and a replaced system prompt, from an empty
  directory. Claude Code still adds context of its own, about 650 tokens of
  environment and account details. Each trial's `interface` entry says this.
- The Opus 5.5 reply to task 1 is byte for byte the same as
  `examples/write/accepted`, line breaks included. The same model wrote that
  example, so the match says little about either.
- Haiku 5.5 did not get task 2: it needs bytes accepted in task 1.

Each trial directory has `prompt.txt` (the exact prompt sent), `reply.txt`
(the `result` the CLI returned, unedited), `response.json` (the model the
API reported, the turn count and token counts) and `fixture.config`. The
tests check that each `prompt.txt` is the prompt the runner gives for that
task and base.

## Record a model trial

For a Claude model, run the script. It sends the prompt, saves everything
above, and labels the trial with the verdict the runner gives:

```sh
scripts/record-claude-trial.sh write  my-label claude-sonnet-5-5
scripts/record-claude-trial.sh revise my-label claude-sonnet-5-5 write/my-label
```

For any other model or chat interface, record it by hand. A reply counts as
a model trial only when its prompt, its raw reply and the model's identity
were recorded. Put it under `trials/<task>/<label>/`:

```text
trials/write/<label>/
  prompt.txt       the exact prompt you sent
  reply.txt        the exact reply, unedited
  fixture.config
```

```erlang
%% trials/write/<label>/fixture.config
{source, model_trial}.
{model, "the model's name and version, as the provider gives it"}.
{interface, "where you ran it, such as a chat window or an API, and any settings"}.
{recorded_on, "2026-11-23"}.
{expect, wrong_answer}.          % the verdict `check` gave
```

A revise trial adds `{base, "write/<label>"}.`, naming the task 1 trial whose
accepted bytes its prompt contains. The demo replays trials with the
examples, counts them separately, and fails if a fixture under `trials/` is
missing any of these.

## Where things are

| file | what it does |
| --- | --- |
| `src/wasm_bytes.erl` | the command line and the demo |
| `src/wb_check.erl` | the stages, from reply text to verdict, and the revision check |
| `src/wb_hex.erl` | strict hex decoding |
| `src/wb_profile.erl` | the module profile |
| `src/wb_layout.erl` | reads section headers, for the profile and the diff |
| `src/wb_exec.erl` | runs the calls in a fresh worker with fuel and a deadline |
| `src/wb_task.erl` | the tasks, the reference predicates, the inputs |
| `src/wb_diff.erl` | the byte diff |
| `src/wb_report.erl` | what gets printed |
| `src/wb_fixture.erl` | loads saved replies and checks their provenance |
| `scripts/record-claude-trial.sh` | records a trial with a Claude model, headless |

## Run the tests

```sh
rebar3 eunit
```

## Notes

- erlang_wasm is pinned to 0.11.0, the latest release on Hex. The 0.11.1
  tag on GitHub changes documentation only and is not on Hex.
- erlang_wasm has no public call that lists a module's imports, memories or
  start function. `wb_layout` reads them from the section headers, and only
  for bytes `wasm:compile/1` has accepted. The export's type comes from
  `wasm:func_type_of/2`.
- The next step is a larger set of tasks, comparing whole-module hex with
  function-body hex and with WAT.
