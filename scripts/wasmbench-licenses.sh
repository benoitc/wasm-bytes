#!/bin/sh
# Looks up the license of each GitHub repository a usable WasmBench binary was
# collected from, and writes datasets/wasmbench/licenses.config, which
# `bin/wasm-bytes prepare wasmbench --sample N' reads to keep only openly
# licensed binaries in the sample.
#
#   scripts/wasmbench-licenses.sh CORPUS-DIRECTORY
#
# CORPUS-DIRECTORY is the output of a corpus run, such as _build/cases. Needs
# the GitHub CLI, authenticated. A license is the one GitHub reports for the
# repository today, which may differ from when WasmBench collected the binary;
# a repository that is gone is recorded as unavailable.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORPUS=$1
OUT="$ROOT/datasets/wasmbench/licenses.config"
mkdir -p "$(dirname "$OUT")"

REPOS=$(grep -h -o '<<"github: [^ "]*' "$CORPUS"/wasmbench/read/*/case.config |
        sed 's/<<"github: //' | sort -u)
{
    echo "%% The license GitHub reported on $(date +%F) for each repository a usable"
    echo "%% WasmBench binary came from. Written by scripts/wasmbench-licenses.sh."
    for R in $REPOS; do
        if ! L=$(gh api "repos/$R" --jq '.license.spdx_id // "none"' 2>/dev/null); then
            L=unavailable
        fi
        echo "{<<\"$R\">>, <<\"$L\">>}."
    done
} > "$OUT"
grep -c '^{' "$OUT"
