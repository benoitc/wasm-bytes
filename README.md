# wasm-bytes

**A language model wrote a working WebAssembly binary directly.** In one recorded attempt, Claude Sonnet 5.5 received an English description of a function and replied with the 54 bytes below. Decode the hex and you have a complete `.wasm` file. The model supplied the header, section lengths, and instructions itself. [Exact prompt](trials/write/claude-sonnet-5-5-1/prompt.txt) · [Unedited reply](trials/write/claude-sonnet-5-5-1/reply.txt)

George Xenos and Sotiris Giannopoulos asked a model to write native executables byte by byte. This repository tries two of their tasks with WebAssembly: write a program from a description, then revise it from its bytes. WebAssembly gives the experiment a portable target. The same reply can run inside an Erlang application or in a standalone WebAssembly runtime. [Programming in the Machine Code Space](https://sgiannopoulos.github.io/blog/machine-code-programming/)

## From an English rule to 54 bytes

The prompt asks for one function, `retry`, that takes a 32-bit integer and decides whether to retry an HTTP request. Return 1 for status 429 or any status from 500 through 599 inclusive. Return 0 for everything else. This was Sonnet’s entire answer:

```text
00 61 73 6d 01 00 00 00
01 06 01 60 01 7f 01 7f
03 02 01 00
07 09 01 05 72 65 74 72 79 00 00
0a 15 01 13 00 20 00 41 ad 03 46 20 00 41 f4 03 6b 41 e4 00 49 72 0b
```

You can spot the WebAssembly header in the first line and the letters of `retry` (`72 65 74 72 79`) in the fourth. The last line contains the code that makes the decision. In a second recorded trial, Sonnet received these bytes and changed its answers for 408 and 501 while preserving every other tested result. [Revision prompt](trials/revise/claude-sonnet-5-5-1/prompt.txt) · [Revised bytes](trials/revise/claude-sonnet-5-5-1/reply.txt)

The 54 bytes have the SHA-256 `5085ed49…dee7`, recorded with the trial, and every run below reports the hash of the bytes it received. Opus 5.5's recorded reply decodes to the same bytes. So does a constructed example that Opus 5.5 wrote while the checker was being built. [Recorded hash](trials/write/claude-sonnet-5-5-1/module.sha256) · [What the match means](doc/evidence.md#1-the-model-supplied-the-bytes)

## Replay what happened

From the repository root, run this with Erlang/OTP 29 or later and rebar3 installed. The first run fetches the pinned runtime from Hex. Replaying needs no model account.

```sh
bin/wasm-bytes replay
```

The command traces Sonnet's reply to its bytes and their hash. Then it runs five replies through erlang_wasm and the checker. The first four were constructed to trigger one protection each. The last one is the model's reply. The output ends like this:

```text
2. What erlang_wasm and the checker did with five replies
  [constructed] examples/write/stack-mismatch
      invalid             erlang_wasm's validator refused the module before anything ran: type mismatch
  [constructed] examples/write/has-memory
      interface_mismatch  erlang_wasm validated it; the checker's interface rules refused it before it was instantiated:
                          - it defines 1 memory; the profile allows no memory
                          - it also exports "memory"; the profile allows one export
  [constructed] examples/write/loops-on-negative
      execution_failure   erlang_wasm's fuel budget stopped 14 calls; the other 514 calls returned
  [constructed] examples/write/misses-599
      wrong_answer        erlang_wasm ran every call within its limits; the reference check found input 599 expected 1, got 0
  [model trial] trials/write/claude-sonnet-5-5-1
      pass                validated, accepted by the interface rules, ran within its limits; 528 of 528 answers match the reference
```

Validation checks whether the instructions form a legal program. A legal program can still loop or return a wrong answer. Fuel stops the loop. Only the comparison with an independently written Erlang function catches the wrong answer at 599. The model's reply passed every one of these checks on all 528 tested inputs. [Detailed evidence](doc/evidence.md) · [Execution limits and verdicts](doc/runner.md)

**Why use `erlang_wasm`?** It decodes, validates, and executes WebAssembly on the Erlang virtual machine. An Erlang application can receive the same guest bytes on different host architectures without rebuilding the guest. Here the checker requires a single exported function and rejects imports, memory, and start functions before execution. In particular, the guest has no imported host functions through which to read a file or open a socket. [erlang_wasm](https://github.com/benoitc/erlang_wasm) · [Checker’s interface rules](src/wb_profile.erl)

## Run the same bytes in Wasmtime

To test portability, run the module in a second engine. This command calls it in erlang_wasm and in Wasmtime on the same 528 inputs. It compares both engines with the reference answers. It needs Wasmtime on your `PATH`. The rest of wasm-bytes does not.

```sh
bin/wasm-bytes compare write trials/write/claude-sonnet-5-5-1/reply.txt
```

```text
  erlang_wasm  0.11.0, received the same bytes: 528 of 528 match the reference
  wasmtime     50.0.1, received the same bytes: 528 of 528 match the reference
  agree        528 of 528 inputs give the same result in both engines
  first diff   none
  verdict      pass
```

The same comparison passed on macOS on arm64, and in Linux containers on arm64 and on emulated x86_64. All three runs used one Mac. A run on separate x86_64 hardware is still pending. You can also load the module from JavaScript. [Platform runs and how to repeat them](doc/evidence.md#3-the-same-bytes-in-another-engine-and-on-other-hosts) · [Node.js example](doc/runner.md#call-the-module-from-nodejs)

## Try your own model

1. **Send the write prompt.** Run the command below and paste its entire output into your model. This includes the retry rule, the required function signature, and the instructions for formatting the reply.

   ```sh
   bin/wasm-bytes prompt write
   ```

2. **Save and check the first reply.** Copy the full response into a plain-text file named `reply.txt`. Keep any explanation or code fences the model included. Those count towards its verdict. Whitespace between hex pairs is allowed.

   ```sh
   bin/wasm-bytes check write reply.txt
   ```

   If it passes, keep `reply.txt` as the base for the next prompt. If it fails, the diagnostic above `verdict` tells you where this attempt stopped.

3. **Send the revision prompt.** The command below checks the base and prints a prompt containing its actual bytes. Paste that output into the model. This time 408 should change from 0 to 1, and 501 from 1 to 0. Every other answer should stay the same. [See a filled-in revision prompt](prompts/revise.example.txt)

   ```sh
   bin/wasm-bytes prompt revise --base reply.txt
   ```

4. **Check the revision.** Save the complete second reply as `revised.txt` and compare it with the same base.

   ```sh
   bin/wasm-bytes check revise revised.txt --base reply.txt
   ```

   Read `diff` to see which bytes changed. Read `changes` and `request` to see what those edits did. A passing revision changes the answers for 408 and 501 and preserves the other 526 tested answers.

## Read a failed check

Try this saved example. It contains a valid module with one mistake at the top of the retry range.

```sh
bin/wasm-bytes check write examples/write/misses-599/reply.txt
```

```text
  wrong    1 answer differs from the reference
           input 599: expected 1, got 0
  answers  527 of 528 match the reference
  verdict  wrong_answer
```

The program ran, but it declined to retry status 599. That single input is enough to explain why this reply cannot serve as a revision base. Other replies fail earlier, for example when the model wraps its answer in a sentence. [Guide to every verdict](doc/runner.md)

## Explore the results

- See what each claim rests on, with the commands and run records. [Evidence](doc/evidence.md)
- Run `bin/wasm-bytes demo` to replay everything locally. The summary compares each observed verdict with its saved label. A deliberately wrong example counts as a successful replay when it fails as expected.
- Read the first five recorded trials and their limits. Opus and Sonnet each passed both tasks on their recorded attempts. Haiku missed the write task and received no revision prompt. [Project status](doc/status.md)
- Save a run from your own model so someone else can replay it. [Record a trial](trials/README.md)
