#!/bin/sh
# Builds the GitHub Pages site into OUT (default _build/site): the README and
# the guides as HTML pages, the images they show, and the DX-Ball pan demo
# built from the recorded replies. Needs pandoc, and what bin/wasm-bytes needs.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/_build/site}
REPO_URL=${REPO_URL:-https://github.com/benoitc/wasm-bytes}

command -v pandoc >/dev/null || { echo "build-site: pandoc is needed" >&2; exit 2; }
rm -rf "$OUT"
mkdir -p "$OUT/doc" "$OUT/trials" "$OUT/demo/pan"

# One page: GitHub-flavoured Markdown in, with GitHub's heading anchors, so
# links such as dx-ball.md#hear-it keep working.
render() {
    src=$1 dest=$2 root=$3
    title=$(sed -n 's/^# //p' "$ROOT/$src" | head -1)
    pandoc --from gfm --to html5 --standalone \
        --template "$ROOT/site/template.html" --lua-filter "$ROOT/site/links.lua" \
        --metadata source="$src" --metadata repo="$REPO_URL" \
        --metadata pagetitle="$title" --variable root="$root" \
        --output "$OUT/$dest" "$ROOT/$src"
}

render README.md index.html ""
for page in "$ROOT"/doc/*.md; do
    name=$(basename "$page" .md)
    render "doc/$name.md" "doc/$name.html" "../"
done
render trials/README.md trials/README.html "../"

cp -R "$ROOT/doc/media" "$OUT/doc/media"
cp "$ROOT/site/style.css" "$OUT/style.css"

# The demo page, with the modules checked again and embedded.
"$ROOT/bin/wasm-bytes" pan-demo --no-open >/dev/null
cp "$ROOT"/_build/pan-demo/* "$OUT/demo/pan/"

# Plain files: no Jekyll processing on GitHub Pages.
touch "$OUT/.nojekyll"
echo "build-site: $OUT"
