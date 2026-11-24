# Can an AI write a WebAssembly file you can run?

WebAssembly, or Wasm, is a file format for programs. Browsers, servers and apps can load one and run it in a sandbox. Normally a compiler writes these files. We asked a language model, Claude Sonnet 5.5, to write one itself, byte by byte, and then ran its reply exactly as it came back. This is one recorded trial, in three steps.

## 1. What we asked

> If a server says “too many requests” or returns a server error, should the app try again?

Picture a weather app fetching the forecast. We asked the model for a Wasm file with one function, `retry`, that the app calls with the server's status code. Here is the rule in plain English:

- **Try again** (return `1`) for status 429, “too many requests”, and for every server error, 500 through 599.
- **Stop** (return `0`) for any other number.

The prompt also says how to reply: only the bytes, with no explanation and no code. [The exact prompt](trials/write/claude-sonnet-5-5-1/prompt.txt)

## 2. What the model gave us

**The model’s actual reply**

<div class="reply">

```text
00 61 73 6d 01 00 00 00
01 06 01 60 01 7f 01 7f
03 02 01 00
07 09 01 05 72 65 74 72 79 00 00
0a 15 01 13 00 20 00 41 ad 03 46 20 00 41 f4 03 6b 41 e4 00 49 72 0b
```

</div>

Each pair of characters is one byte, written in hexadecimal. Together, these 54 bytes are the whole program. We didn't add, remove or fix any of them. The first four, `00 61 73 6d`, mark the file as Wasm. `72 65 74 72 79` spells `retry`, the name the app calls. The last line is the decision itself. [The unedited reply](trials/write/claude-sonnet-5-5-1/reply.txt) · [Every byte, explained](doc/evidence.md#1-the-model-supplied-the-bytes)

## 3. What happened when we ran it

<div class="outcomes calls">
<p class="outcome"><strong>retry(429)</strong> returned <code>1</code>, so the app should try again.</p>
<p class="outcome"><strong>retry(404)</strong> returned <code>0</code>, so it should stop.</p>
</div>

A 404 means the page doesn't exist, so asking again won't help. The app still makes the request and waits between attempts. The file only decides whether to try again.

To replay the saved result without a model account, run this from the repository root. You need Erlang/OTP 29 and rebar3. [Setup](doc/try.md#before-you-start)

```sh
bin/wasm-bytes check write trials/write/claude-sonnet-5-5-1/reply.txt
```

```text
  hex      54 bytes
  wasm     decodes and validates (erlang_wasm 0.11.0)
  profile  one function, exported as retry : (i32) -> (i32); no imports, memory or start
  calls    528 inputs, each in a fresh instance; fuel 10000 and a 1000 ms deadline per call
  answers  528 of 528 match the reference
  verdict  pass
```

## How do we know it worked?

Erlang's Wasm runtime, [erlang_wasm](https://github.com/benoitc/erlang_wasm), checked that the file was valid and ran it with limits: a fresh copy for every call, a small budget of work, a one-second deadline, and nothing imported, so no way to reach files or the network. The checker compared its answers against expected results, written separately in Erlang, on 528 inputs: every status from 100 through 599 and 28 other numbers. All 528 matched. Wasmtime, a separate Wasm runtime, ran the same bytes as a second check and gave the same 528 answers. [The evidence, and how to repeat it](doc/evidence.md)

## Where does the sound demo come from?

The demo plays each beep on the left or the right, following the ball. The REA team recovered that sound rule from the 1996 game DX-Ball, we put the rule in a prompt, and Claude wrote the Wasm that the demo runs.

[Hear the demo](https://benoitc.github.io/wasm-bytes/demo/pan/) · [How the demo was made](doc/dx-ball.md) · [Demo pages the models wrote](https://benoitc.github.io/wasm-bytes/demo/ui/)

## How does it do on public test collections?

We asked Sonnet 599 questions from the WebAssembly test suite, real files from WasmBench, and programming contest problems from CodeContests. Each was one of two questions.

- **Can the model read these bytes and predict the answer?** It did for 544 of 556 programs. Most misses were the right number, wrapped in Markdown or words. [Example: what does `f(2147483647, 1)` return?](doc/datasets.md#read-the-bytes-predict-the-answer)
- **Can it write bytes that pass the tests?** It did for 30 of 31 single instructions, but only 7 of 12 contest problems. [Example: a file that adds two numbers](doc/datasets.md#write-bytes-that-pass-the-tests)

[How the questions were chosen, what the run cost, and how it scales](doc/datasets.md) · [What we found](doc/status.md)

## How do I try it with my own model?

1. Print the prompt and paste all of it into your model.

   ```sh
   bin/wasm-bytes prompt write
   ```

2. Save the whole reply, unedited, as `reply.txt` and check it.

   ```sh
   bin/wasm-bytes check write reply.txt
   ```

`pass` means the file gave the right answer on all 528 inputs. Any other verdict says where the attempt stopped. [Setup, smaller models, asking for a change, and reading a failed check](doc/try.md)

## Where can I read more?

- [Every trial, model by model](doc/status.md)
- [How to read a check, and every verdict](doc/runner.md)
- [A larger function: `digit_sum` adds the digits of a number](doc/status.md#a-slightly-larger-program-digit_sum)
- [Record a trial so someone else can replay it](trials/README.md)

The idea comes from George Xenos and Sotiris Giannopoulos’s experiment in writing native executables byte by byte. Wasm lets one reply run inside an Erlang application, in a browser, or in a standalone runtime such as Wasmtime. [Programming in the Machine Code Space](https://sgiannopoulos.github.io/blog/machine-code-programming/)

## License

Apache License 2.0, the same license as erlang_wasm. [License](LICENSE)
