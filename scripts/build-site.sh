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
# The two modules every page loads: the replies pan-demo put in modules.js,
# with the prompts that produced them.
PAN_DIR=$(sed -n 's/.*"reply":"\(trials\/pan\/[^"]*\)\/reply.txt".*/\1/p' "$ROOT/_build/pan-demo/modules.js")
REV_DIR=$(sed -n 's/.*"reply":"\(trials\/reverse\/[^"]*\)\/reply.txt".*/\1/p' "$ROOT/_build/pan-demo/modules.js")
MOD_MODEL=$(sed -n 's/^{model, "\([^"]*\)"}\./\1/p' "$ROOT/$PAN_DIR/fixture.config" | sed 's/, digest .*//')
MODULES_LINE="<p>Modules it loads: written by <code>$MOD_MODEL</code>, from the <a href=\"$REPO_URL/blob/main/$PAN_DIR/prompt.txt\">pan prompt</a> (<a href=\"$REPO_URL/blob/main/$PAN_DIR/reply.txt\">reply</a>) and the <a href=\"$REPO_URL/blob/main/$REV_DIR/prompt.txt\">reverse prompt</a> (<a href=\"$REPO_URL/blob/main/$REV_DIR/reply.txt\">reply</a>).</p>"
cat > "$GALLERY" <<'INTRO'
# Pages the models wrote

Each page below is a model's whole reply to a page prompt, published as it came back. The page is the last of three prompts. It runs WebAssembly that a model wrote first, from two module prompts.

<p><img src="../../doc/media/ui-flow.svg" alt="The flow: the pan prompt gives the Original module, the reverse prompt the Reversed one, pan-demo puts both in modules.js, then the ui prompt gives the page, which loads modules.js in your browser and pans each beep by screen_pan(x) / 500." style="width:100%;max-width:560px;display:block;margin:8px auto 16px"></p>

1. **Module prompt.** The [pan prompt](@REPO@/blob/main/@PAN_DIR@/prompt.txt) asks a model for the bytes of a WebAssembly module whose `screen_pan(x)` follows DX-Ball's recovered rule. The runner checks the reply before anything uses it.
2. **Reverse prompt.** The [reverse prompt](@REPO@/blob/main/@REV_DIR@/prompt.txt) gives the model its accepted module and asks for the same module with the stereo reversed. The runner checks that reply too.
3. **Page prompt.** `bin/wasm-bytes pan-demo` puts the two accepted modules into `modules.js`, as base64. Then the [ui prompt](@REPO@/blob/main/prompts/ui.txt) asks a model for the page that loads `modules.js` and calls `screen_pan` on the module you select. The page prompt describes `modules.js`, but contains neither the module prompts nor the bytes.

Every page here loads the same `modules.js`, with the two modules `@MOD_MODEL@` wrote in steps 1 and 2. So a page can be written by one model and run modules written by another. Each entry gives the verdict of the browser checks: a page that passes uses those modules for every value it shows or plays, turns its sound on with one tap, asks for media playback so that an iPhone's silent switch should not mute it, and fits a phone screen. Open a page on its own to hear it on an iPhone. [How the modules were made](../../doc/dx-ball.html) · [How the pages are checked](../../doc/ui.html)

To run the three prompts yourself, from the repository folder:

```sh
# 1. Send pan-prompt.txt to a model, and save its whole reply as pan.txt.
bin/wasm-bytes prompt pan > pan-prompt.txt
bin/wasm-bytes check pan pan.txt
# 2. Send reverse-prompt.txt, and save the reply as reversed.txt.
bin/wasm-bytes prompt reverse --base pan.txt > reverse-prompt.txt
bin/wasm-bytes check reverse reversed.txt --base pan.txt
# 3. Send ui-prompt.txt, and save the reply as page.html.
bin/wasm-bytes prompt ui > ui-prompt.txt
bin/wasm-bytes check ui page.html --original pan.txt --reversed reversed.txt
```

INTRO
sed -e "s|@REPO@|$REPO_URL|g" -e "s|@PAN_DIR@|$PAN_DIR|g" -e "s|@REV_DIR@|$REV_DIR|g" \
    -e "s|@MOD_MODEL@|$MOD_MODEL|g" "$GALLERY" > "$GALLERY.tmp" && mv "$GALLERY.tmp" "$GALLERY"

# Whether a trial received today's ui prompt, baseline or guided.
current() {
    cmp -s "$1/prompt.txt" "$PROMPTS/ui.txt" || cmp -s "$1/prompt.txt" "$PROMPTS/ui.guided.txt"
}

# One entry: the modules it loads, the page, its verdict, its links, and a
# sandboxed preview.
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

$MODULES_LINE
$note<p><a href="$label/index.html">Open the page</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/prompt.txt">Its page prompt</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/reply.txt">Its reply on GitHub</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/fixture.config">Model, settings and verdict</a></p>
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
