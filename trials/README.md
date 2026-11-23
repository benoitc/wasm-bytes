# Model trials

This directory holds replies that were sent to a model and recorded: the
exact prompt, the exact reply and the model's identity. Only these count as
evidence of what a model can do, and each is one sample.

Each trial is a directory `trials/<task>/<label>/` with `prompt.txt`,
`reply.txt`, `fixture.config`, and for trials recorded by
`scripts/record-claude-trial.sh`, `response.json`. The README at the root of
the repository lists the trials recorded so far and how to record one.
`bin/wasm-bytes demo` replays every trial and fails on one that is missing
its prompt, its reply or its model.
