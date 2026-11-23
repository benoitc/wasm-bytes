# Record and replay a model trial

A trial preserves one attempt so another person can see exactly what the model received, what it returned, and which verdict the runner gave it. For a complete example, open the saved files from one write attempt. [Prompt](write/claude-sonnet-5-5-1/prompt.txt) · [Reply](write/claude-sonnet-5-5-1/reply.txt) · [Model, settings, date, and verdict](write/claude-sonnet-5-5-1/fixture.config)

Run these commands from the repository root. The second one replays the revision against the same write reply that the model saw.

```sh
bin/wasm-bytes check write trials/write/claude-sonnet-5-5-1/reply.txt
bin/wasm-bytes check revise trials/revise/claude-sonnet-5-5-1/reply.txt --base trials/write/claude-sonnet-5-5-1/reply.txt
```

For results across models and the limits of these samples, see the [project status](../doc/status.md).

## Record an attempt from any chat or API

1. Choose a new label for the attempt and create `trials/write/<label>/`. Save the output of `bin/wasm-bytes prompt write` there as `prompt.txt`. Send that text to the model.
2. Save the complete reply as `reply.txt` in the same directory. Run `bin/wasm-bytes check write trials/write/<label>/reply.txt`, substituting your label.
3. If `check` printed a byte count on its `hex` line, record the hash of the decoded module, so that every engine and host can be checked against the same bytes. Run `xxd -r -p reply.txt > module.wasm && shasum -a 256 module.wasm > module.sha256` in the trial directory, then delete `module.wasm`. A test checks that the hash matches the reply.
4. Add `fixture.config`. Fill in the model version, interface and settings, date, and the verdict that `check` printed. A failed attempt is worth recording too.

```erlang
{source, model_trial}.
{model, "model name and version"}.
{interface, "chat or API name and settings used"}.
{recorded_on, "YYYY-MM-DD"}.
{expect, wrong_answer}.
```

For the larger `digit_sum` task, follow the same steps with `digits` in place of `write`: `bin/wasm-bytes prompt digits` for the prompt, `trials/digits/<label>/` for the files, and `bin/wasm-bytes check digits` for the verdict.

A `ui` trial is a whole HTML page, not hex. Its prompt comes from `bin/wasm-bytes prompt ui`, and `bin/wasm-bytes check ui trials/ui/<label>/reply.txt` checks it in Chrome. The check needs Node and Chrome. [Browser checks](../doc/ui.md)

The DX-Ball pair works the same way. Use `pan` for the first prompt, then `reverse` with `{base, "pan/<label>"}.` for the second. The second prompt comes from `bin/wasm-bytes prompt reverse --base trials/pan/<label>/reply.txt`.

For a revision, start with a passing write trial. Create `trials/revise/<label>/` and save the output of `bin/wasm-bytes prompt revise --base trials/write/<base-label>/reply.txt` as its prompt. Send it, save the raw reply, and check it with that same base. Include the same fields in its config and add `{base, "write/<base-label>"}.` using the actual write label.

Run `bin/wasm-bytes demo` to confirm the new trial replays as labelled. The demo reports missing trial information and counts recorded attempts separately from examples constructed to demonstrate verdicts.

## Use the guided prompt

Both one-prompt tasks also have a guided prompt. It adds a reference card to the same task: the module layout, how numbers are encoded, and the byte of each instruction with the order of its operands. It also asks the model to work in numbered steps. Use it to test whether a model can encode a program when it does not have to recall the opcode table. Keep the baseline prompt for results you want to compare with earlier trials. [Guided write prompt](../prompts/write.guided.txt) · [Guided digit_sum prompt](../prompts/digits.guided.txt)

```sh
bin/wasm-bytes prompt write --guided
bin/wasm-bytes prompt digits --guided
```

Record which prompt a trial received. Add `{prompt_variant, guided}.` to its `fixture.config`. Both recorders do this when you set `PROMPT=guided`, for example `PROMPT=guided scripts/record-ollama-trial.sh write my-label MODEL`. The revision task has only the baseline prompt.

## Record with the Claude Code CLI

With an authenticated Claude Code CLI, the recorder sends the prompt and writes the trial files for you. Choose an unused label and a model available to your account. Run the second command after the first trial passes.

```sh
scripts/record-claude-trial.sh write my-label claude-sonnet-5-5
scripts/record-claude-trial.sh revise my-label claude-sonnet-5-5 write/my-label
scripts/record-claude-trial.sh digits my-label claude-sonnet-5-5
scripts/record-claude-trial.sh pan my-label claude-sonnet-5-5
scripts/record-claude-trial.sh reverse my-label claude-sonnet-5-5 pan/my-label
scripts/record-claude-trial.sh ui my-label claude-sonnet-5-5
```

The recorder also saves `response.json` with the model identity, turn count, and token usage reported by the CLI. It saves `module.sha256` too, the hash of the module the reply decodes to, in `shasum -a 256` format. It runs in an empty directory with tools, MCP servers, and settings disabled and a replacement system prompt. Claude Code still supplies some environment and account context. [Recording script](../scripts/record-claude-trial.sh)

## Record with a local model through Ollama

With an Ollama server running on this machine, the recorder sends the prompt to a local model. No account or API key is involved. Choose an unused label and a model from `ollama list`.

```sh
scripts/record-ollama-trial.sh write  my-label inkling-2-mini:26b-a5b-nvfp4
scripts/record-ollama-trial.sh digits my-label inkling-2-mini:26b-a5b-nvfp4
scripts/record-ollama-trial.sh revise my-label inkling-2-mini:26b-a5b-nvfp4 write/my-label
```

The recorder uses `/api/chat` with the same system prompt as the Claude recorder and Ollama's default sampling. `reply.txt` holds the answer field only. A model with a thinking mode returns its trace separately, and the recorder saves it as `thinking.txt`. `response.json` records the model's digest, the Ollama version, and the token counts. Set `THINK` to choose a thinking level and `OLLAMA_HOST` to use another server. [Recording script](../scripts/record-ollama-trial.sh)
