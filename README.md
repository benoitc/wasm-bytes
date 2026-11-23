# wasm-bytes

wasm-bytes tests whether a language model can write and revise a working WebAssembly program one byte at a time. You give the model a prompt, save its reply, and run a local checker. The reply is the program itself, with each byte written as two hexadecimal digits.

The first prompt gives the model this rule for retrying an HTTP request (`i32` means a 32-bit integer).

> retry(x) returns 1 when x is 429,
> returns 1 when x is from 500 through 599 inclusive,
> and returns 0 for every other i32 value, including negative values.

The second prompt gives the model its own passing bytes and asks it to change two answers. [Full write prompt](prompts/write.txt) · [Full revision prompt from a recorded run](trials/revise/claude-sonnet-5-5-1/prompt.txt)

## Try a recorded reply

From the repository root, with Erlang/OTP 29 or later and rebar3 installed, run the command below. The first run fetches the pinned WebAssembly runtime from Hex. Replaying a saved reply needs no model account or API key.

```sh
bin/wasm-bytes check write trials/write/claude-sonnet-5-5-1/reply.txt
```

The report ends with the number of matching answers and a verdict.

```text
  answers  528 of 528 match the reference
  verdict  pass
```

Sonnet’s reply begins with `00 61 73 6d 01 00 00 00`, the WebAssembly header. The checker decoded the full 54-byte reply, found the requested function, and got the expected answer every time it called it. [Prompt sent to Sonnet](trials/write/claude-sonnet-5-5-1/prompt.txt) · [Raw reply](trials/write/claude-sonnet-5-5-1/reply.txt)

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

## Use the program the model wrote

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

## Explore the results

- Run `bin/wasm-bytes demo` to replay everything locally. The summary compares each observed verdict with its saved label. A deliberately wrong example counts as a successful replay when it fails as expected.
- Read the first five recorded trials and their limits. Opus and Sonnet each passed both tasks on their recorded attempts. Haiku missed the write task and received no revision prompt. [Project status](doc/status.md)
- Save a run from your own model so someone else can replay it. [Record a trial](trials/README.md)
