#!/bin/sh
# Fetches CodeContests parquet files at the pinned revision and exports the
# problems that could fit an integer function, for the codecontests track.
#
#   scripts/fetch-codecontests.sh [FILE ...]
#
# FILE names a file under data/ in the dataset, such as
# valid-00000-of-00001-5e672c5751f060d3.parquet. Without one, it fetches the
# three the sample came from: the valid and test splits (52 MB and 63 MB) and
# the first of the 39 training files (180 MB). Each file is checked against
# the SHA-256 the dataset's repository records for it at the pinned revision.
# The export needs Python 3; pyarrow is installed in _build/venv on first use.
# Prints the JSON lines file to pass to
# `bin/wasm-bytes prepare codecontests --from'.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT/_build/datasets/code_contests"
REV=802411c3010cb00d1b05bad57ca77365a3c699d6
BASE="https://huggingface.co/datasets/deepmind/code_contests"
if [ $# -eq 0 ]; then
    set -- valid-00000-of-00001-5e672c5751f060d3.parquet \
           test-00000-of-00001-9c49eeff30aacaa8.parquet \
           train-00000-of-00039-e991a271dbfa9925.parquet
fi

mkdir -p "$DIR"
TREE=$(curl -sSL --fail "https://huggingface.co/api/datasets/deepmind/code_contests/tree/$REV/data")
SOURCES=""
for F in "$@"; do
    WANT=$(printf '%s' "$TREE" | python3 -c '
import json, sys
name = sys.argv[1]
for item in json.load(sys.stdin):
    if item["path"] == "data/" + name:
        print(item["lfs"]["oid"])' "$F")
    [ -n "$WANT" ] || { echo "fetch-codecontests: no data/$F at revision $REV" >&2; exit 2; }
    if [ ! -f "$DIR/$F" ]; then
        curl -sSL --fail -o "$DIR/$F.part" "$BASE/resolve/$REV/data/$F"
        mv "$DIR/$F.part" "$DIR/$F"
    fi
    echo "$WANT  $DIR/$F" | shasum -a 256 -c - >/dev/null ||
        { echo "fetch-codecontests: $F does not have the recorded SHA-256" >&2; exit 1; }
    SPLIT=$(printf '%s' "$F" | sed -E 's/^([a-z]+)-([0-9]+)-of-([0-9]+).*/\1-\2/; s/^(valid|test)-00000$/\1/')
    SOURCES="$SOURCES $SPLIT=$DIR/$F"
done

if [ ! -x "$ROOT/_build/venv/bin/python" ]; then
    python3 -m venv "$ROOT/_build/venv"
fi
"$ROOT/_build/venv/bin/python" -c 'import pyarrow' 2>/dev/null ||
    "$ROOT/_build/venv/bin/pip" install -q pyarrow
# shellcheck disable=SC2086
"$ROOT/_build/venv/bin/python" "$ROOT/scripts/codecontests-export.py" "$DIR/candidates.jsonl" $SOURCES >&2
echo "$DIR/candidates.jsonl"
