# How to read a check

`bin/wasm-bytes check` prints the stages a reply reached. Read the final `verdict` and the diagnostic above it. A reply can decode into valid WebAssembly and still give the wrong answer. [Walk through a check](../README.md)

| Verdict | What it means | Where to look |
| --- | --- | --- |
| `pass` | The module has the requested interface and every tested input gave the expected answer. | The `answers` line gives the count. A passing write reply can be the base of a revision. |
| `too_large` | The reply exceeds 65,536 bytes of text or 4,096 decoded bytes. | The report gives the measured size and limit. |
| `malformed_hex` | The text could not be read as hex byte pairs. | Look for an empty reply, an unpaired digit, prose, or a code fence. For an offending character the report gives its line and column. |
| `malformed_wasm` | The bytes could not be decoded as a WebAssembly module. | Read the decoder message. A truncated section can declare more bytes than are present. |
| `invalid` | The module decodes but breaks a WebAssembly validation rule. | The validation message can identify an instruction type or stack mismatch. |
| `interface_mismatch` | The module validates but has the wrong shape for this task. | Read `profile`. The module must contain exactly one function, export it as `retry` with one 32-bit integer argument and result, and have no other exports, imports, memory, or start function. |
| `execution_failure` | The module could not start, or a call failed to return a result. | Read `failed` for a trap, fuel exhaustion, deadline, or instantiation error. |
| `wrong_answer` | The function ran and at least one answer differed from the reference. | Read `wrong` for the inputs, expected values, and actual results. |
| `runner_error` | The checker or its WebAssembly runtime encountered an internal error. | Keep the diagnostic when reporting the problem. The reply has no score. |

For scripts, `check` exits with 0 on a pass, 1 for a failed reply or refused revision base, and 2 for a runner or invocation error. To check pasted text, run `bin/wasm-bytes check write -`, paste the reply, then press Ctrl-D on a new line. Keep a copy if you plan to revise it.

## What a pass covers

The checker calls `retry` on every status from 100 through 599, plus 28 other integers. These include negative numbers, 32-bit boundaries, and numbers whose low bits match a status of interest. Each answer is compared with a reference function written in Erlang from the task description. [Test inputs and reference functions](../src/wb_task.erl)

The checker verifies the module's interface before running it. Each call starts with fresh instance state and has a budget of 10,000 fuel units and a 1,000 ms deadline. The checker replaces a worker that hits its deadline. After three deadlines it marks the remaining inputs as untested. [Interface checks](../src/wb_profile.erl) · [Execution limits](../src/wb_exec.erl)

A revision check first rechecks the base against the write task. It compares the new bytes with the base and labels each group of edits by its location in the original module. When both modules run, it also compares their answers on the same inputs. A changed length field in `diff` is a byte edit. An input listed under `changes` is an observable difference in what the program did. [Revision checks](../src/wb_check.erl)

## Find a worked example

The fixtures under `examples/` were prepared and checked while building the runner. Each directory has the reply and a `fixture.config` explaining the expected verdict. Some include `module.wat`, the human-readable WebAssembly source for the bytes.

| To explore | Example |
| --- | --- |
| The bytes and source of a passing function | [Accepted write](../examples/write/accepted/) |
| Why a sentence around correct bytes fails | [Prose around hex](../examples/write/prose-around-hex/) |
| How the checker reports an extra behavior change | [Revision that also changes 429](../examples/revise/replaces-429/) |
| What happens when new instructions leave length fields out of date | [Revision with stale lengths](../examples/revise/stale-lengths/) |

Run `bin/wasm-bytes demo` to replay the entire collection alongside the recorded trials. Run `rebar3 eunit` for the automated test suite.
