---
name: document-wasm-bytes
description: Write or review human-facing wasm-bytes documentation when prompts, commands, verdicts, or recorded results change.
---

# Document wasm-bytes for a first-time reader

Start with the reader's decision. Someone trying the experiment needs to know what to send the model, what to save, which command to run, and what the result lets them do next. Someone reading a trial needs its actual prompt, raw reply, and observed verdict.

- Keep the first runnable example in the root README small enough to follow with a saved reply and no model account. Use a concrete input and expected answer to explain the task.
- For prompt changes, compare the instructions with `bin/wasm-bytes prompt write` or render `prompt revise --base` using a passing write reply. Link the sendable prompt. A revision template still containing `{{MODULE_HEX}}` needs rendering first.
- For command or verdict changes, replay the documented command from the repository root. Quote the lines that answer the reader's question and explain their consequence. For example, a write pass supplies the base for a revision. A wrong answer identifies a test input to examine.
- For results, trace the claim to the files under `trials/` and give the sample size. Use `examples/` to explain how a verdict works. Scope a pass to the inputs checked.
- Put detailed verdict definitions in `doc/runner.md`, dated findings in `doc/status.md`, and recording instructions in `trials/README.md`. Follow changed relative links from their containing page and check that sample output still matches the saved reply.
