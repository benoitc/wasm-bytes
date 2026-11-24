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

# The demo pages the models wrote, for every ui trial: each reply as it is,
# beside the same modules.js, and a page listing them. Pages that answered
# today's ui prompt come first, then those that answered an earlier one; a
# trial's prompt.txt says which. Within each, pages that passed every
# browser check come first. The list shows each page in a sandboxed frame
# and links to it on its own, since Safari on iOS may not play audio from a
# frame.
GALLERY="$ROOT/_build/site-src/ui.md"
PROMPTS="$ROOT/_build/site-src/prompts"
mkdir -p "$(dirname "$GALLERY")" "$PROMPTS" "$OUT/demo/ui"
"$ROOT/bin/wasm-bytes" prompt ui > "$PROMPTS/ui.txt"
"$ROOT/bin/wasm-bytes" prompt ui --guided > "$PROMPTS/ui.guided.txt"
cat > "$GALLERY" <<'INTRO'
# Pages the models wrote

Each page below is a model's whole reply, published as it came back. Each entry links the prompt the model received and gives the verdict of the browser checks. A page that passes uses the recorded `screen_pan` modules for every value it shows or plays, turns its sound on with one tap, asks for media playback so that an iPhone's silent switch should not mute it, and fits a phone screen. Open a page on its own to hear it on an iPhone. [How the pages are checked](../../doc/ui.html)

INTRO

# Whether a trial received today's ui prompt, baseline or guided.
current() {
    cmp -s "$1/prompt.txt" "$PROMPTS/ui.txt" || cmp -s "$1/prompt.txt" "$PROMPTS/ui.guided.txt"
}

# One entry: the page, its verdict, its links, and a sandboxed preview.
gallery_entry() {
    dir=${1%/}
    label=$(basename "$dir")
    model=$(sed -n 's/^{model, "\([^"]*\)"}\./\1/p' "$dir/fixture.config" | sed 's/, digest .*//')
    verdict=$(sed -n 's/^{expect, \([a-z_]*\)}.*/\1/p' "$dir/fixture.config")
    heading=$model note=""
    if grep -q '^{prompt_variant, guided}' "$dir/fixture.config"; then
        heading="$model, guided prompt"
        note="<p>Reply to the guided prompt, which adds one paragraph on how to request media playback on an iPhone.</p>
"
    fi
    if [ "$verdict" = pass ]; then
        note="$note<p>Verdict: <code>pass</code>, every browser check passed.</p>
"
    else
        note="$note<p>Verdict: <code>$verdict</code>. <a href=\"../../doc/ui.html#what-the-models-wrote\">Which check failed, and what it means</a></p>
"
    fi
    mkdir -p "$OUT/demo/ui/$label"
    cp "$dir/reply.txt" "$OUT/demo/ui/$label/index.html"
    cp "$ROOT/_build/pan-demo/modules.js" "$OUT/demo/ui/$label/modules.js"
    cat >> "$GALLERY" <<PAGE
### $heading

$note<p><a href="$label/index.html">Open the page</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/prompt.txt">The prompt it received</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/reply.txt">Its reply on GitHub</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/fixture.config">Model, settings and verdict</a></p>
<iframe src="$label/index.html" title="Demo page written by $heading" sandbox="allow-scripts" allow="autoplay" loading="lazy" style="width:100%;height:720px;border:1px solid var(--line);border-radius:8px"></iframe>

PAGE
}

# One section: the trials of one round, passing pages first.
gallery_section() {
    round=$1 title=$2 intro=$3
    dirs=""
    for dir in "$ROOT"/trials/ui/*/; do
        if [ "$round" = current ]; then current "$dir" || continue; else current "$dir" && continue; fi
        dirs="$dirs $dir"
    done
    [ -n "$dirs" ] || return 0
    printf '## %s\n\n%s\n\n' "$title" "$intro" >> "$GALLERY"
    for dir in $dirs; do grep -q '^{expect, pass}' "$dir/fixture.config" && gallery_entry "$dir"; done
    for dir in $dirs; do grep -q '^{expect, pass}' "$dir/fixture.config" || gallery_entry "$dir"; done
}

gallery_section current "Today's prompt" \
    "These pages answered the [ui prompt]($REPO_URL/blob/main/prompts/ui.txt) as it is now. It describes how the page looks as well as what it does, after the hand-written [demo](../pan/)."
gallery_section earlier "The first prompt" \
    "These pages answered the [first version of the prompt]($REPO_URL/blob/main/prompts/ui.first.txt), which said what the page does but not how it looks."
pandoc --from gfm --to html5 --standalone \
    --template "$ROOT/site/template.html" \
    --metadata source="prompts/ui.txt" --metadata repo="$REPO_URL" \
    --metadata pagetitle="Pages the models wrote" --variable root="../../" \
    --output "$OUT/demo/ui/index.html" "$GALLERY"

# Plain files: no Jekyll processing on GitHub Pages.
touch "$OUT/.nojekyll"
echo "build-site: $OUT"
