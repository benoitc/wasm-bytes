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

# The demo pages the models wrote, for every ui trial that passed its checks:
# each reply as it is, beside the same modules.js, and a page listing them.
# The list shows each one in a sandboxed frame and links to it on its own,
# since Safari on iOS may not play audio from a frame.
GALLERY="$ROOT/_build/site-src/ui.md"
mkdir -p "$(dirname "$GALLERY")" "$OUT/demo/ui"
cat > "$GALLERY" <<'INTRO'
# Pages the models wrote

Each page below is a model's whole reply to the [ui prompt](https://github.com/benoitc/wasm-bytes/blob/main/prompts/ui.txt), published as it came back. Every one passed the browser checks: it uses the recorded `screen_pan` modules for every value it shows or plays, its sound turns on with one tap, and it fits a phone screen. Open a page on its own to hear it on an iPhone. [How the pages are checked](../../doc/ui.html)

INTRO
for dir in "$ROOT"/trials/ui/*/; do
    label=$(basename "$dir")
    grep -q '^{expect, pass}' "$dir/fixture.config" || continue
    model=$(sed -n 's/^{model, "\([^"]*\)"}\./\1/p' "$dir/fixture.config")
    mkdir -p "$OUT/demo/ui/$label"
    cp "$dir/reply.txt" "$OUT/demo/ui/$label/index.html"
    cp "$ROOT/_build/pan-demo/modules.js" "$OUT/demo/ui/$label/modules.js"
    cat >> "$GALLERY" <<PAGE
## $model

<p><a href="$label/index.html">Open the page</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/reply.txt">Its reply on GitHub</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/fixture.config">Model, settings and verdict</a></p>
<iframe src="$label/index.html" title="Demo page written by $model" sandbox="allow-scripts" allow="autoplay" loading="lazy" style="width:100%;height:720px;border:1px solid var(--line);border-radius:8px"></iframe>

PAGE
done
pandoc --from gfm --to html5 --standalone \
    --template "$ROOT/site/template.html" \
    --metadata source="prompts/ui.txt" --metadata repo="$REPO_URL" \
    --metadata pagetitle="Pages the models wrote" --variable root="../../" \
    --output "$OUT/demo/ui/index.html" "$GALLERY"

# Plain files: no Jekyll processing on GitHub Pages.
touch "$OUT/.nojekyll"
echo "build-site: $OUT"
