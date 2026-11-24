# Can an AI write a WebAssembly file you can run?

Most programs start as code that a person writes. A tool called a compiler then turns that code into a file your computer can run. WebAssembly, or Wasm for short, is one kind of file like this. Web browsers, servers and apps can load a Wasm file and run it safely, walled off from everything else. On this page, you'll see what happens when you skip the code and the compiler, and ask an AI model, Claude Sonnet 5.5, to write the file itself, one byte at a time.

## 1. What was the model asked?

> If a server says “too many requests” or returns a server error, should the app try again?

Picture a weather app. It asks a server for the forecast. Sometimes the server answers with an error code instead, such as 404 when the page doesn't exist, or 429 when the app is asking too often. We asked the model for a Wasm file with one small function, `retry`. Your app gives it the code, and it answers. Here is the rule in plain English:

- **Try again**, answer `1`, for code 429 and for any server error, from 500 to 599.
- **Stop**, answer `0`, for any other code.

We also told the model to reply with nothing but the bytes of the file: no explanation and no code. [Read the exact prompt](trials/write/claude-sonnet-5-5-1/prompt.txt)

## 2. What did the model write?

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

This is the whole program. Each pair of characters, such as `6d` or `7f`, stands for one byte: a number from 0 to 255, written in base 16. Together, these 54 bytes make the complete Wasm file, exactly as the model sent it. Nobody added, removed or fixed a single one. A few are easy to spot. The first four, `00 61 73 6d`, mark the file as Wasm. `72 65 74 72 79` spells the word `retry`. The last line is the rule itself, as steps the computer follows. [See the reply as it arrived](trials/write/claude-sonnet-5-5-1/reply.txt) · [See what every byte means](doc/evidence.md#1-the-model-supplied-the-bytes)

## 3. What happened when it ran?

<div class="outcomes calls">
<p class="outcome"><strong>retry(429)</strong> answered <code>1</code>, so the app should try again.</p>
<p class="outcome"><strong>retry(404)</strong> answered <code>0</code>, so it should stop.</p>
</div>

Asking again for a page that doesn't exist won't help, so stopping on 404 is right. Your app still sends the request and waits between tries. The file only makes the yes-or-no decision.

You can replay this result on your own computer, without an account with any AI company. Install Erlang/OTP 29 and rebar3 ([setup](doc/try.md#before-you-start)), then run this from the project folder:

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

Read the last two lines: all 528 answers were right, so the file passes.

## How do you know it worked?

First, erlang_wasm, a program that runs Wasm files, confirmed that the file follows the rules of Wasm. It then ran the file under strict limits: a fresh start for every call, a small budget of work, one second at most, and no way to reach your files or the network. Next, the checker called `retry` with 528 codes, every one from 100 to 599 plus 28 unusual numbers, and compared each answer with the right one, worked out separately. All 528 matched. Finally, as a second opinion, Wasmtime, a Wasm program made by another team, ran the same bytes and gave the same 528 answers. [See the evidence, and repeat each check yourself](doc/evidence.md)

## Where does the sound demo come from?

The demo moves a ball across the screen and plays each beep from the left or the right, following the ball. The REA team recovered that sound rule from the 1996 game DX-Ball, we put the rule in a prompt, and Claude wrote the Wasm file that the demo runs.

[Hear the demo](https://benoitc.github.io/wasm-bytes/demo/pan/) · [How the demo was made](doc/dx-ball.md) · [Demo pages the models wrote](https://benoitc.github.io/wasm-bytes/demo/ui/)

## How does it do on harder tests?

We also gave Sonnet 599 questions from public collections: the official WebAssembly tests, real Wasm files found on the web, and programming contest problems. Each was one of two questions.

- **Can the model read the bytes and predict the answer?** Shown only the bytes of a file, it gave the right answer for 544 of 556 files. Most of its misses were the right number with formatting or words around it. [Example: what a file that adds two numbers returns](doc/datasets.md#read-the-bytes-predict-the-answer)
- **Can it write bytes that pass the tests?** It wrote a passing file for 30 of 31 single operations, such as adding two numbers, but for only 7 of 12 contest problems. [Example: writing a file that adds two numbers](doc/datasets.md#write-bytes-that-pass-the-tests)

[How the questions were chosen, what the run cost, and how it scales](doc/datasets.md) · [Everything we found](doc/status.md)

## How do you try it with your own model?

1. Print the prompt, then paste all of it into the AI model you want to test.

   ```sh
   bin/wasm-bytes prompt write
   ```

2. Save the model's whole reply, without editing it, in a file named `reply.txt`. Then check it.

   ```sh
   bin/wasm-bytes check write reply.txt
   ```

If the last line says `pass`, the file gave the right answer for all 528 codes. Any other word tells you where it went wrong. [The full guide: setup, smaller models, asking for a change, and reading a failed check](doc/try.md)

## Where can you read more?

- [Every trial, model by model](doc/status.md)
- [How to read a check, and what each result means](doc/runner.md)
- [A bigger function: adding up the digits of a number](doc/status.md#adding-up-a-numbers-digits)
- [How to save a trial so someone else can replay it](trials/README.md)

The idea comes from George Xenos and Sotiris Giannopoulos, who showed that AI models can read and write native programs byte by byte. Wasm adds one thing: the same file runs in a browser, inside an Erlang application, or in Wasmtime. [Programming in the Machine Code Space](https://sgiannopoulos.github.io/blog/machine-code-programming/)

## License

Apache License 2.0, the same license as erlang_wasm. [License](LICENSE)
