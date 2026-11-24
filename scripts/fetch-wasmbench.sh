#!/bin/sh
# Fetches and unpacks the pinned WasmBench archive for a corpus run of the
# wasmbench track.
#
#   scripts/fetch-wasmbench.sh [DIRECTORY]
#
# Downloads filtered-binaries-metadata.7z (1.14 GB) from WasmBench's v1.0
# release into DIRECTORY (default _build/datasets/wasmbench), checks its
# SHA-256 against the pinned one, and unpacks it there (5.5 GB). Needs curl and
# 7-Zip (`7zz' or `7z'; on macOS, `brew install sevenzip'). Prints the
# directory to pass to `bin/wasm-bytes prepare wasmbench --from'.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:-$ROOT/_build/datasets/wasmbench}
URL=https://github.com/sola-st/WasmBench/releases/download/v1.0/filtered-binaries-metadata.7z
SHA256=2dffbe0120ad5857734ba6ac16b2c789f2fe2f9dda814e0168b6faccf79b58fe
ARCHIVE="$DIR/filtered-binaries-metadata.7z"

SEVENZIP=$(command -v 7zz || command -v 7z || true)
[ -n "$SEVENZIP" ] || { echo "fetch-wasmbench: 7-Zip is needed (7zz or 7z)" >&2; exit 2; }

mkdir -p "$DIR"
if [ ! -f "$ARCHIVE" ]; then
    curl -sSL --fail -o "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null ||
    { echo "fetch-wasmbench: $ARCHIVE does not have the pinned SHA-256" >&2; exit 1; }
if [ ! -f "$DIR/extracted/filtered.pretty.json" ]; then
    "$SEVENZIP" x -y -o"$DIR/extracted" "$ARCHIVE" >/dev/null
fi
echo "$DIR/extracted"
