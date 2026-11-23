# Evidence for the three claims

This page records what was run to support three claims about one recorded reply. Each section gives the command that repeats a run and the files that preserve it. Read it to check a claim yourself, or to see what was verified and on which hosts. The claims cover one function, `retry`, and the five attempts recorded under `trials/`. The runs below were recorded on 23 November 2026. [Project status](status.md) · [How a check works](runner.md)

1. A language model supplied the executable bytes directly.
2. erlang_wasm validates and runs those bytes under explicit limits.
3. The same bytes work in another WebAssembly engine and on more than one host platform.

## 1. The model supplied the bytes

Claude Sonnet 5.5 received the write prompt and returned 161 bytes of text: hex pairs, spaces, and line breaks. They decode to a 54-byte module. Run this to see the prompt as sent, the reply as received, and the module section by section:

```sh
bin/wasm-bytes trace trials/write/claude-sonnet-5-5-1
```

```text
Module: the 54 bytes the hex decodes to, nothing added or changed
  0x0000  00 61 73 6d                                      magic number: \0asm
  0x0004  01 00 00 00                                      version 1
  0x0008  01 06                                            type section, 6 bytes follow
  0x000a  01 60 01 7f 01 7f                                  function types
  0x0010  03 02                                            function section, 2 bytes follow
  0x0012  01 00                                              which type each function has
  0x0014  07 09                                            export section, 9 bytes follow
  0x0016  01 05 72 65 74 72 79 00 00                         exports: name, kind, index
  0x001f  0a 15                                            code section, 21 bytes follow
  0x0021  01 13 00 20 00 41 ad 03 46 20 00 41 f4 03 6b 41    function bodies: the instructions
          e4 00 49 72 0b

  size       54 bytes
  sha256     5085ed49ca1c432946f77ed39efe794a68d5e1622ee3edf67f85f5abaa37dee7
  recorded   module.sha256 holds the same hash
```

Every section length in that table came from the model. The runner decodes hex pairs and refuses anything else. It never adds a byte or recomputes a length. [Hex decoder](../src/wb_hex.erl)

To check the hash without the runner, decode the reply with `xxd` and compare it with the recorded hash. This prints `module.wasm: OK`.

```sh
xxd -r -p trials/write/claude-sonnet-5-5-1/reply.txt > module.wasm
shasum -a 256 -c trials/write/claude-sonnet-5-5-1/module.sha256
```

`wasm-tools print` (version 1.256.0) reads the same bytes as the program below: `x == 429`, or `x - 500` below 100 as an unsigned comparison.

```text
(module
  (type (;0;) (func (param i32) (result i32)))
  (export "retry" (func 0))
  (func (;0;) (type 0) (param i32) (result i32)
    local.get 0
    i32.const 429
    i32.eq
    local.get 0
    i32.const 500
    i32.sub
    i32.const 100
    i32.lt_u
    i32.or
  )
)
```

The trial directory preserves the rest of the attempt. `prompt.txt` is byte for byte the output of `bin/wasm-bytes prompt write`, and a test keeps it that way. `reply.txt` is the `result` field that the Claude Code CLI returned, unedited. `response.json` records `claude-sonnet-5-5` as the model the API reported, one turn, and an empty tool list. [Trial files](../trials/write/claude-sonnet-5-5-1/)

**Read this with three limits in mind.** It is one sample. The model was reached through Claude Code with tools, MCP servers, and settings off and a replacement system prompt, but Claude Code still added about 650 tokens of its own context. The same 54 bytes also appear in two other places: in the recorded Opus 5.5 reply, and in `examples/write/accepted`. That example was written by Opus 5.5 while the checker was being built. Both trials produced this encoding in recorded runs with no tools, so they did not copy it. The match does mean the example is not independent of the Opus trial.

## 2. erlang_wasm validates and runs them under limits

Run this to check five replies and see which protection decided each outcome. Four are examples constructed to trigger one protection each. The fifth is the recorded model reply.

```sh
bin/wasm-bytes replay
```

| Reply | Kind | Verdict | Decided by |
| --- | --- | --- | --- |
| [stack-mismatch](../examples/write/stack-mismatch/) | constructed | `invalid` | erlang_wasm's validator, through `wasm:compile/1`. The body leaves two values where its type allows one. Nothing is instantiated. |
| [has-memory](../examples/write/has-memory/) | constructed | `interface_mismatch` | The checker's interface rules, applied after erlang_wasm validates the module and before it is instantiated. The module defines and exports a memory. erlang_wasm reports the export's type. The checker reads imports, memories, and the start function from the section headers. |
| [loops-on-negative](../examples/write/loops-on-negative/) | constructed | `execution_failure` | erlang_wasm's fuel limit. Each of the 14 negative inputs used up its 10,000 units and stopped. The other 514 calls returned. |
| [misses-599](../examples/write/misses-599/) | constructed | `wrong_answer` | Not erlang_wasm: the module is legal and every call returns within its limits. The checker's reference function finds that input 599 returns 0 instead of 1. |
| [Sonnet's reply](../trials/write/claude-sonnet-5-5-1/) | model trial | `pass` | All of the above. 528 of 528 answers match the reference. |

The limits come from two places. erlang_wasm provides the validator, the fuel budget, and a worker process with a deadline. The checker configures them: 10,000 fuel and 1,000 ms per call, with a fresh instance for every call. The checker adds its own rules: a 4,096-byte size cap, the interface rules, and the reference answers. Because the profile allows no imports, the module has no host function through which it could reach a file or a socket. The replay does not reach a deadline, because fuel stops these loops first. A test covers the deadline path. [Execution limits](../src/wb_exec.erl) · [Interface rules](../src/wb_profile.erl) · [Deadline test](../test/wb_exec_tests.erl)

## 3. The same bytes in another engine and on other hosts

Run this to call the module in erlang_wasm and in Wasmtime on all 528 inputs and compare both with the reference. It needs Wasmtime on your `PATH`, or its path in `WASMTIME`. Nothing else in wasm-bytes needs Wasmtime.

```sh
bin/wasm-bytes compare write trials/write/claude-sonnet-5-5-1/reply.txt
```

```text
  module       54 bytes, sha256 5085ed49ca1c432946f77ed39efe794a68d5e1622ee3edf67f85f5abaa37dee7
  host         macOS 27.2, arm64; Erlang/OTP 29.1.2
  inputs       528, each compared with the write task's reference answer
  erlang_wasm  0.11.0, received the same bytes: 528 of 528 match the reference
  wasmtime     50.0.1, received the same bytes: 528 of 528 match the reference
  agree        528 of 528 inputs give the same result in both engines
  first diff   none
  verdict      pass
```

Each engine hashes the bytes it received. erlang_wasm hashes the bytes passed to `wasm:compile/1`. Wasmtime's hash is computed from the `module.wasm` file read back from disk. Wasmtime runs as `wasmtime run -W fuel=10000 -W timeout=1s --invoke retry module.wasm <input>`, once per input. Its fuel units are not the same as erlang_wasm's, so the two budgets only bound each engine. They do not measure the same work. When a result differs, `first diff` shows the input, the reference answer, and both engines' results. [Comparison](../src/wb_compare.erl)

The same command ran on three host configurations. Each run wrote a record with the host, runtimes, module hash, and result:

| Host | How it ran | erlang_wasm | Wasmtime | Module SHA-256 | Result | Record |
| --- | --- | --- | --- | --- | --- | --- |
| macOS 27.2, arm64 | directly on an Apple silicon Mac | 0.11.0, OTP 29.1.2: 528 of 528 | 50.0.1: 528 of 528 | `5085ed49…dee7` | `pass` | [darwin-arm64](../evidence/runs/darwin-arm64.config) |
| Debian 13, aarch64 | Linux container on the same Mac, native CPU | 0.11.0, OTP 29.1.2: 528 of 528 | 50.0.1: 528 of 528 | `5085ed49…dee7` | `pass` | [linux-aarch64](../evidence/runs/linux-aarch64.config) |
| Debian 13, x86_64 | Linux container on the same Mac, x86_64 emulated by OrbStack | 0.11.0, OTP 29.1.2: 528 of 528 | 50.0.1: 528 of 528 | `5085ed49…dee7` | `pass` | [linux-x86_64](../evidence/runs/linux-x86_64.config) |

To repeat the Linux runs, use Docker. The script builds an image with Erlang/OTP 29 and the Wasmtime release, copies the repository into the container, and writes the record to `evidence/runs/`.

```sh
scripts/platform-check.sh linux/arm64
scripts/platform-check.sh linux/amd64
```

On an arm64 host, the `linux/amd64` run is emulated. Under emulation the Erlang VM does not boot with its default JIT memory mapping, so the script starts it with `+JMsingle true`. The flag changes how the VM maps its own code. It does not change how either engine runs the module. The record notes the flag. [Platform script](../scripts/platform-check.sh)

**What these runs establish.** On one Mac, erlang_wasm and Wasmtime gave the reference answer on all 528 inputs for the same 54 bytes. The same held on a second operating system, Linux, and with the x86_64 builds of both engines. The two engines also agree on the constructed failures, for example at input 599 and on fuel exhaustion. Run `compare` on any reply under `examples/` to see the first discrepancy.

**What remains pending.** All three runs used one physical machine. Linux ran in a virtual machine on it, and x86_64 was emulated. A run on separate x86_64 hardware has not been recorded. Neither has a run on Windows. On such a host, run `scripts/platform-check.sh linux/amd64` without emulation, or run `bin/wasm-bytes compare` directly with `--record evidence/runs`.

## The scope of these claims

These results cover one 54-byte function, the 528 inputs in [the task definition](../src/wb_task.erl), and the five recorded attempts. Opus and Sonnet passed both tasks on their single recorded attempts. Haiku's write attempt was valid but wrong on 526 inputs. The results say nothing about how often a model succeeds, about other models, or about larger programs. [Trial results](status.md)
