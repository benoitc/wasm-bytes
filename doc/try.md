# Try it yourself

This guide shows you how to replay the recorded `retry` trial on your own computer, run the model's file with other tools, and ask your own AI model the same question. Use it when you want to test a model that isn't in the recorded trials, or check a model's reply before you rely on it. Run every command from the project folder.

## Before you start

You need Erlang/OTP 29 or later and rebar3. The first time you run a command, it downloads erlang_wasm, the program this project uses to run Wasm files, and builds it. You don't need an account with any AI company.

```sh
git clone https://github.com/benoitc/wasm-bytes.git
cd wasm-bytes
bin/wasm-bytes replay
```

`replay` checks the model's saved reply and four broken examples, and tells you which check stopped each broken one. The model's reply ends with this line:

```text
  [model trial] trials/write/claude-sonnet-5-5-1
      pass                validated, accepted by the interface rules, ran within its limits; 528 of 528 answers match the reference
```

## Run the file with other tools

The reply is the whole `.wasm` file, written as text. If you have `xxd` and [Wasmtime](https://wasmtime.dev/), you can turn the text back into a file and ask it about codes 429 and 404 yourself:

```sh
xxd -r -p trials/write/claude-sonnet-5-5-1/reply.txt > retry.wasm
wasmtime run -W fuel=10000 --invoke retry retry.wasm 429
wasmtime run -W fuel=10000 --invoke retry retry.wasm 404
```

You'll see `1`, then `0`. Wasmtime also prints a warning that this way of calling a function is still experimental. You can ignore it. [Call the same file from Node.js](runner.md#call-the-module-from-nodejs)

To run all 528 test codes in both erlang_wasm and Wasmtime, and confirm that both received exactly the same bytes:

```sh
bin/wasm-bytes compare write trials/write/claude-sonnet-5-5-1/reply.txt
```

```text
  erlang_wasm  0.11.0, received the same bytes: 528 of 528 match the reference
  wasmtime     50.0.1, received the same bytes: 528 of 528 match the reference
  agree        528 of 528 inputs give the same result in both engines
  verdict      pass
```

![A prompt asks Sonnet to write retry. Its 54-byte hex reply becomes retry.wasm. Wasmtime calls retry(429) and returns 1, then calls retry(404) and returns 0.](media/retry-replay.gif)

## Ask your own model

1. **Send the prompt.** Run the command below and paste everything it prints into your model. It includes the retry rule, the function the file must provide, and how to format the reply. For a small model, or one that runs on your own computer, add `--guided`. That version lists the byte for each step and explains how to build the file. [Guided prompts](../trials/README.md#use-the-guided-prompt)

   ```sh
   bin/wasm-bytes prompt write
   ```

2. **Save and check the reply.** Copy the model's full answer into a plain text file named `reply.txt`. If the model added an explanation or wrapped the bytes in a code block, leave it in: the check counts that against the model. Spaces and line breaks between pairs of characters are fine.

   ```sh
   bin/wasm-bytes check write reply.txt
   ```

   If the last line says `pass`, keep `reply.txt` for the next step. If it says anything else, the line just above it tells you where this attempt went wrong. [What each result means](runner.md)

3. **Ask for a change.** The command below checks your saved reply, then prints a new prompt that includes its bytes. Paste that prompt into the model. This time, the app should also try again after a timeout, code 408, and stop when a server says it doesn't support the request, code 501. Every other answer should stay the same. [See a complete change request](../prompts/revise.example.txt)

   ```sh
   bin/wasm-bytes prompt revise --base reply.txt
   ```

4. **Check the change.** Save the model's full second answer as `revised.txt`, then compare it with your first reply.

   ```sh
   bin/wasm-bytes check revise revised.txt --base reply.txt
   ```

   `diff` shows which bytes changed. `changes` and `request` show what those changes did to the answers. The change passes when only the answers for 408 and 501 changed and the other 526 stayed the same.

Sonnet's own change passed. It added 14 bytes, and only the answers for 408 and 501 changed. [The change request it got](../trials/revise/claude-sonnet-5-5-1/prompt.txt) · [Its reply](../trials/revise/claude-sonnet-5-5-1/reply.txt)

## Read a failed check

This saved example is a file that runs but has one mistake: it says stop for code 599, the last server error.

```sh
bin/wasm-bytes check write examples/write/misses-599/reply.txt
```

```text
  wrong    1 answer differs from the reference
           input 599: expected 1, got 0
  answers  527 of 528 match the reference
  verdict  wrong_answer
```

One wrong answer is enough to fail, and you can't use this file as the starting point for a change. Other replies fail earlier, for example when the model wraps its bytes in a sentence. [Every result, and where to look](runner.md)

## Notes

- A pass only covers the 528 codes the checker tried: every code from 100 to 599 and 28 other numbers. It doesn't tell you how often a model gets it right. [What a pass covers](runner.md#what-a-pass-covers)
- To share a trial so someone else can replay it, save the prompt, the reply and which model you used. [Record a trial](../trials/README.md)
- To try another task, replace `write` with `digits` for adding up digits, or with `pan` for the DX-Ball sound. For the DX-Ball change, use `reverse` instead of `revise`. [Results for every task](status.md)
