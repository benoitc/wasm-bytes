# wasm-bytes

Can you describe a function to a language model and use its reply as a program? In this experiment, Claude Sonnet 5.5 answered with 54 bytes of WebAssembly (Wasm). Those bytes define a function that an application can load and call. The model wrote the whole file, from the Wasm header to the final instruction. [Exact prompt](trials/write/claude-sonnet-5-5-1/prompt.txt) · [Unedited reply](trials/write/claude-sonnet-5-5-1/reply.txt)

The idea comes from George Xenos and Sotiris Giannopoulos’s experiment in writing native executables byte by byte. Using Wasm gives us a way to take one model reply and run it inside an Erlang application, in JavaScript, or in a standalone runtime such as Wasmtime. [Programming in the Machine Code Space](https://sgiannopoulos.github.io/blog/machine-code-programming/)

## What would an application do with these bytes?

Imagine an HTTP client fetching a page. The server replies with status 429 (“Too Many Requests”). Should the client try again later? We asked the model to put one small piece of that decision into a function called `retry`. Under the rule in the prompt, 429 and every status from 500 through 599 mean “retry”. Every other integer means “stop”.

The HTTP client is the **host**. It loads the Wasm module and calls `retry` by name. Wasm calls a function exposed this way an **export**. The host passes in one 32-bit integer and gets one back. It interprets the result and handles the network request and its timing itself.

| What the client received | Call into Wasm | What the client learns |
| --- | --- | --- |
| 429 Too Many Requests | `retry(429)` → `1` | Schedule another attempt. |
| 503 Service Unavailable | `retry(503)` → `1` | Schedule another attempt. |
| 404 Not Found | `retry(404)` → `0` | Stop retrying this request. |

We then asked the model to change the policy while keeping the same function name and argument. With the revised module, the client’s existing call `retry(408)` changes from 0 to 1, and `retry(501)` changes from 1 to 0. The other 526 tested answers stay the same. [Revision prompt](trials/revise/claude-sonnet-5-5-1/prompt.txt) · [Revised reply](trials/revise/claude-sonnet-5-5-1/reply.txt)

## From the model’s reply to a function call

Here is Sonnet’s entire answer to the first prompt. Each pair of hexadecimal digits represents one byte of the file.

```text
00 61 73 6d 01 00 00 00
01 06 01 60 01 7f 01 7f
03 02 01 00
07 09 01 05 72 65 74 72 79 00 00
0a 15 01 13 00 20 00 41 ad 03 46 20 00 41 f4 03 6b 41 e4 00 49 72 0b
```

The first eight bytes identify the file as a Wasm module and give its format version. The fourth line contains the name `retry` (`72 65 74 72 79`), and the last line contains the function body. To make the same call as the client above, run these commands from the repository root with `xxd` and Wasmtime installed.

```sh
xxd -r -p trials/write/claude-sonnet-5-5-1/reply.txt > retry.wasm
wasmtime run -W fuel=10000 --invoke retry retry.wasm 429
wasmtime run -W fuel=10000 --invoke retry retry.wasm 404
```

The calls print `1` and `0`. The first command simply converts the model’s text to bytes. The next two load those bytes and call the exported function. [Call the same file from Node.js](doc/runner.md#call-the-module-from-nodejs)

## How can you check a model’s answer before using it?

With Erlang/OTP 29 or later and rebar3 installed, replay the experiment locally. The first run fetches the pinned runtime from Hex. You can replay the saved replies without a model account.

```sh
bin/wasm-bytes replay
```

**Can it run safely within this task’s limits?** The Erlang runtime, `erlang_wasm`, validates the module’s instructions. The checker then requires exactly one exported function and rejects imports, memory, and start functions. That gives `retry` no host function for opening a socket or reading a file. Each test call gets fresh state, a budget of 10,000 units of work (“fuel”), and a one-second deadline. The replay includes a deliberately looping example so you can see what happens when a call runs out of fuel. [erlang_wasm](https://github.com/benoitc/erlang_wasm) · [Execution limits and verdicts](doc/runner.md)

**Does it make the right decision?** The checker compares each result with an independently written Erlang function. Sonnet’s module matched on all 528 inputs. Another example runs successfully but returns 0 for status 599, where the client expects 1. You can see that failure below. [Replay evidence](doc/evidence.md)

**Does the same file work elsewhere?** This command compares erlang_wasm and Wasmtime on the same 528 inputs. It checks the module’s SHA-256 fingerprint so you can verify both engines received identical bytes. Wasmtime must be on your `PATH` for this comparison.

```sh
bin/wasm-bytes compare write trials/write/claude-sonnet-5-5-1/reply.txt
```

Both engines matched all 528 answers on macOS arm64 and in Linux containers on arm64 and emulated x86_64. All three runs used one Mac. [Recorded module fingerprint](trials/write/claude-sonnet-5-5-1/module.sha256) · [Platform runs and how to repeat them](doc/evidence.md#3-the-same-bytes-in-another-engine-and-on-other-hosts)

## A second function that does arithmetic

`digit_sum` takes an integer and adds its decimal digits. A host calling `digit_sum(407)` gets 11 back because 4 + 0 + 7 = 11. Calling `digit_sum(-407)` gives the same answer because the function ignores the sign. It uses the same Wasm interface as `retry` (one integer in, one integer out), but here the returned number is the answer to a calculation.

This task tests whether the model can encode a loop that extracts one digit at a time and keeps a running total. Here is how to check Haiku’s 95-byte reply. It matched the reference on all 1,353 tested inputs, including the smallest signed 32-bit integer, −2147483648, whose digits sum to 47. [Exact prompt](prompts/digits.txt) · [Recorded replies and results](doc/status.md#a-slightly-larger-program-digit_sum)

```sh
bin/wasm-bytes check digits trials/digits/claude-haiku-5-5-1/reply.txt
```

## Try your own model

1. **Send the write prompt.** Run the command below and paste its entire output into your model. This includes the retry rule, the required function signature, and the instructions for formatting the reply. For a small or local model, add `--guided`. That version includes the byte of each instruction and a step-by-step method. [Guided prompts](trials/README.md#use-the-guided-prompt)

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
- Read the recorded trials and their limits. Opus and Sonnet passed every task on their recorded attempts. A local model run through Ollama failed both tasks with the baseline prompts, then passed `digit_sum` with the guided prompt. [Project status](doc/status.md)
- Save a run from your own model so someone else can replay it. [Record a trial](trials/README.md)

## License

Apache License 2.0, the same license as erlang_wasm. [License](LICENSE)
