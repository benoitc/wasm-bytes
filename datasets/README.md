# Pinned sources

These files are inputs to the reading and writing tracks. Read this when you need to know where a file came from, or under which license it is kept here. [Reading and writing tracks](../doc/datasets.md)

| File | Source | License |
| --- | --- | --- |
| `spec/i32.wast` | [WebAssembly/testsuite](https://github.com/WebAssembly/testsuite/blob/92a3d806c7d70f5b63f125e6155b8d76304509f1/i32.wast) at commit `92a3d806c7d70f5b63f125e6155b8d76304509f1`, unchanged. SHA-256 `f3b7e8fd641893ea0989a8ab801fce0654d276d27b5cad9cf482291a422cffe8`. | Apache License 2.0, as the test suite is published |
| `wasmbench/licenses.config` | The license GitHub reported on 24 November 2026 for each repository a usable WasmBench binary came from, written by `scripts/wasmbench-licenses.sh` | This project's |

The WasmBench binaries and the CodeContests problems are not kept here. Fetch them with `scripts/fetch-wasmbench.sh` and `scripts/fetch-codecontests.sh`. The cases under `cases/` hold the few that make up each sample, with their origin in each `case.config`: WasmBench binaries only from openly licensed projects, and CodeContests problems under the dataset's CC BY 4.0 license.
