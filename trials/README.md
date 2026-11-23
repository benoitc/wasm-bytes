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

For a revision, start with a passing write trial. Create `trials/revise/<label>/` and save the output of `bin/wasm-bytes prompt revise --base trials/write/<base-label>/reply.txt` as its prompt. Send it, save the raw reply, and check it with that same base. Include the same fields in its config and add `{base, "write/<base-label>"}.` using the actual write label.

Run `bin/wasm-bytes demo` to confirm the new trial replays as labelled. The demo reports missing trial information and counts recorded attempts separately from examples constructed to demonstrate verdicts.

## Record with the Claude Code CLI

With an authenticated Claude Code CLI, the recorder sends the prompt and writes the trial files for you. Choose an unused label and a model available to your account. Run the second command after the first trial passes.

```sh
scripts/record-claude-trial.sh write my-label claude-sonnet-5-5
scripts/record-claude-trial.sh revise my-label claude-sonnet-5-5 write/my-label
```

The recorder also saves `response.json` with the model identity, turn count, and token usage reported by the CLI. It saves `module.sha256` too, the hash of the module the reply decodes to, in `shasum -a 256` format. It runs in an empty directory with tools, MCP servers, and settings disabled and a replacement system prompt. Claude Code still supplies some environment and account context. [Recording script](../scripts/record-claude-trial.sh)
