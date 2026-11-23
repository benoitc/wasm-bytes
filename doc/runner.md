# How to read a check

`bin/wasm-bytes check` prints the stages a reply reached. Read the final `verdict` and the diagnostic above it. A reply can decode into valid WebAssembly and still give the wrong answer. [Walk through a check](../README.md)

| Verdict | What it means | Where to look |
| --- | --- | --- |
| `pass` | The module has the requested interface and every tested input gave the expected answer. | The `answers` line gives the count. A passing write reply can be the base of a revision. |
| `too_large` | The reply exceeds 65,536 bytes of text or 4,096 decoded bytes. | The report gives the measured size and limit. |
| `malformed_hex` | The text could not be read as hex byte pairs. | Look for an empty reply, an unpaired digit, prose, or a code fence. For an offending character the report gives its line and column. |
| `malformed_wasm` | The bytes could not be decoded as a WebAssembly module. | Read the decoder message. A truncated section can declare more bytes than are present. |
| `invalid` | The module decodes but breaks a WebAssembly validation rule. | The validation message can identify an instruction type or stack mismatch. |
| `interface_mismatch` | The module validates but has the wrong shape for this task. | Read `profile`. The module must contain exactly one function, export it under the task's name (`retry` or `digit_sum`) with one 32-bit integer argument and result, and have no other exports, imports, memory, or start function. |
| `execution_failure` | The module could not start, or a call failed to return a result. | Read `failed` for a trap, fuel exhaustion, deadline, or instantiation error. |
| `wrong_answer` | The function ran and at least one answer differed from the reference. | Read `wrong` for the inputs, expected values, and actual results. |
| `runner_error` | The checker or its WebAssembly runtime encountered an internal error. | Keep the diagnostic when reporting the problem. The reply has no score. |

For scripts, `check` exits with 0 on a pass, 1 for a failed reply or refused revision base, and 2 for a runner or invocation error. To check pasted text, run `bin/wasm-bytes check write -`, paste the reply, then press Ctrl-D on a new line. Keep a copy if you plan to revise it.

## Trace, replay, and compare

Three commands follow a recorded reply past the verdict. `trace` prints a trial's prompt as sent, its reply as received, and the module it decodes to, section by section. It also prints the module's SHA-256 and compares it with `module.sha256` in the trial directory. Add `--wasm FILE` to write the module to a file. `replay` is the short account in the README: one trace and five outcomes, each with the check that decided it. [Evidence for each claim](evidence.md)

```sh
bin/wasm-bytes trace trials/write/claude-sonnet-5-5-1
bin/wasm-bytes replay
bin/wasm-bytes compare write trials/write/claude-sonnet-5-5-1/reply.txt
```

`compare` runs a reply in erlang_wasm and in Wasmtime on the same inputs. It reports the hash of the bytes each engine received, how many answers match the reference, and the first input where an engine and the reference disagree. Add `--record DIR` to save the result with the host and runtime versions. Only `compare` needs Wasmtime. Install it, or set `WASMTIME` to its path.

| Verdict | What it means |
| --- | --- |
| `pass` | Both engines gave the reference answer on every input. |
| `reference_differs` | The engines agree on every input, and at least one answer is not the reference answer. Two failed calls count as agreeing, whatever each engine gives as the reason. |
| `engines_differ` | On at least one input the engines disagree. `first diff` shows where. |

`compare` exits with 0 on `pass`, 1 on either other verdict, and 2 when Wasmtime is missing or the reply is not hex.

## What a pass covers

For `retry`, the checker calls the function on every status from 100 through 599, plus 28 other integers. These include negative numbers, 32-bit boundaries, and numbers whose low bits match a status of interest. For `screen_pan`, the DX-Ball task, it makes 641 calls, one for every screen position from 0 through 640. For `digit_sum`, it makes 1,353 calls. They cover 0 through 1000, −1 through −100, powers of ten and their neighbours, the 32-bit limits, and 200 numbers spread over the whole range. Each answer is compared with a reference function written in Erlang from the task description. [Test inputs and reference functions](../src/wb_task.erl)

The checker verifies the module's interface before running it. Each call starts with fresh instance state and has a budget of 10,000 fuel units and a 1,000 ms deadline. The checker replaces a worker that hits its deadline. After three deadlines it marks the remaining inputs as untested. [Interface checks](../src/wb_profile.erl) · [Execution limits](../src/wb_exec.erl)

When many answers are wrong, `first` shows the first wrong input. The wrong inputs are grouped by how far each answer is from the reference. A revision check first rechecks the base against its own task: `write` for `revise`, and `pan` for `reverse`. It compares the new bytes with the base and labels each group of edits by its location in the original module. When both modules run, it also compares their answers on the same inputs. A changed length field in `diff` is a byte edit. An input listed under `changes` is an observable difference in what the program did. [Revision checks](../src/wb_check.erl)

## Find a worked example

The fixtures under `examples/` were prepared and checked while building the runner. Each directory has the reply and a `fixture.config` explaining the expected verdict. Some include `module.wat`, the human-readable WebAssembly source for the bytes.

| To explore | Example |
| --- | --- |
| The bytes and source of a passing function | [Accepted write](../examples/write/accepted/) |
| Why a sentence around correct bytes fails | [Prose around hex](../examples/write/prose-around-hex/) |
| How the checker reports an extra behavior change | [Revision that also changes 429](../examples/revise/replaces-429/) |
| What happens when new instructions leave length fields out of date | [Revision with stale lengths](../examples/revise/stale-lengths/) |

Run `bin/wasm-bytes demo` to replay the entire collection alongside the recorded trials. Run `rebar3 eunit` for the automated test suite.

## Call the module from Node.js

A passing reply already contains an entire `.wasm` file encoded as text. If you have `xxd` and Node.js, you can turn the saved Sonnet reply into a binary file and call its exported function yourself.

```sh
xxd -r -p trials/write/claude-sonnet-5-5-1/reply.txt > retry.wasm
node -e 'const fs = require("node:fs");
  WebAssembly.instantiate(fs.readFileSync("retry.wasm")).then(({instance}) => {
    const {retry} = instance.exports;
    console.log(retry(429), retry(404));
  });'
```

This prints `1 0`. To try your own passing module, substitute its reply file in the first command.
