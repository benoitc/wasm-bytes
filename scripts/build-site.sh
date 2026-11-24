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
        --lua-filter "$ROOT/site/anchors.lua" \
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
# The stylesheet, and the font, its license and the logo it uses.
cp "$ROOT/site/style.css" "$ROOT/site/archivo-latin.woff2" "$ROOT/site/archivo-OFL.txt" \
    "$ROOT/site/enki-logo.svg" "$OUT/"

# The demo page, with the modules checked again and embedded.
"$ROOT/bin/wasm-bytes" pan-demo --no-open >/dev/null
cp "$ROOT"/_build/pan-demo/* "$OUT/demo/pan/"

# The demo pages the models wrote, for every ui trial: each reply as it is,
# beside the same modules.js, and a page listing them, after the DX-Ball
# flow. Pages that answered today's ui prompt come first, then those that
# answered an earlier one; a trial's prompt.txt says which. Within each,
# pages that passed every browser check come first. The list shows each
# page in a sandboxed frame and links to it on its own, since Safari on iOS
# may not play audio from a frame.
GALLERY="$ROOT/_build/site-src/ui.md"
SRC="$ROOT/_build/site-src"
PROMPTS="$SRC/prompts"
mkdir -p "$PROMPTS" "$OUT/demo/ui"
"$ROOT/bin/wasm-bytes" prompt ui > "$PROMPTS/ui.txt"
"$ROOT/bin/wasm-bytes" prompt ui --guided > "$PROMPTS/ui.guided.txt"

# A model's name as a reader knows it: claude-sonnet-5-5 is Claude Sonnet 5.5.
display_name() {
    case $1 in
        claude-*-*)
            rest=${1#claude-} family=${1#claude-}
            family=${family%%-*}
            version=$(printf %s "${rest#*-}" | tr - .)
            initial=$(printf %s "$family" | cut -c1 | tr a-z A-Z)
            echo "Claude $initial${family#?} $version" ;;
        inkling-2-mini*) echo "Inkling 2 Mini" ;;
        *) echo "$1" ;;
    esac
}

# The two sound modules every page loads: the replies pan-demo put in
# modules.js, with the prompts that produced them.
PAN_DIR=$(sed -n 's/.*"reply":"\(trials\/pan\/[^"]*\)\/reply.txt".*/\1/p' "$ROOT/_build/pan-demo/modules.js")
REV_DIR=$(sed -n 's/.*"reply":"\(trials\/reverse\/[^"]*\)\/reply.txt".*/\1/p' "$ROOT/_build/pan-demo/modules.js")
MOD_NAME=$(display_name "$(sed -n 's/^{model, "\([^"]*\)"}\./\1/p' "$ROOT/$PAN_DIR/fixture.config")")

# The DX-Ball flow, as the guide has it: rendered with the guide's links,
# then pointed at the guides from this page's folder.
sed -n '/<!-- flow:start -->/,/<!-- flow:end -->/p' "$ROOT/doc/dx-ball.md" > "$SRC/flow.md"
pandoc --from gfm --to html5 --lua-filter "$ROOT/site/links.lua" --lua-filter "$ROOT/site/anchors.lua" \
    --metadata source="doc/dx-ball.md" --metadata repo="$REPO_URL" "$SRC/flow.md" |
    sed -E 's#href="([^"/\#:][^":]*)"#href="../../doc/\1"#g' > "$SRC/flow.html"

cat > "$GALLERY" <<INTRO
# Pages the models wrote

Each page below is a model's whole reply to a page prompt, published as it came back. Every page loads the same two sound modules, which $MOD_NAME wrote first from two module prompts. So each entry names two authors: the model that wrote the page, and the model that wrote the sound modules it runs. [How the pages are checked](../../doc/ui.html) · [The DX-Ball guide](../../doc/dx-ball.html)

INTRO
cat "$SRC/flow.html" >> "$GALLERY"
cat >> "$GALLERY" <<'STEPS'

## Run the three prompts yourself

From the repository folder, send each printed prompt to a model and save its whole reply under the name shown:

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

STEPS

# Whether a trial received today's ui prompt, baseline or guided.
current() {
    cmp -s "$1/prompt.txt" "$PROMPTS/ui.txt" || cmp -s "$1/prompt.txt" "$PROMPTS/ui.guided.txt"
}

# What a failed browser check means for someone opening the page.
missing() {
    case $1 in
        loads) echo "the page did not load both modules without an error" ;;
        animates) echo "the ball does not move through the positions" ;;
        reading) echo "the page does not show x and the value returned for it" ;;
        sound_on) echo "one tap on Sound does not start the beeps" ;;
        ios_audio) echo "the page never asks for media playback, so an iPhone's silent switch would probably mute it" ;;
        pan) echo "the beeps are not placed by the module's value" ;;
        same_beep) echo "the beep changes between the two modes" ;;
        switch) echo "the mode buttons do not select the module" ;;
        pause) echo "Pause does not hold the ball" ;;
        sound_off) echo "a second tap does not stop the beeps" ;;
        uses_module) echo "the page computes the pan itself instead of calling the module" ;;
        network) echo "the page requests files it should not" ;;
        phone) echo "the page does not fit a phone screen" ;;
        *) echo "$1" ;;
    esac
}

# One entry: who wrote the page and the sound modules, the prompt it
# received, its verdict, its links, and a sandboxed preview.
gallery_entry() {
    dir=${1%/} round=$2
    label=$(basename "$dir")
    page_name=$(display_name "$(sed -n 's/^{model, "\([^"]*\)"}\./\1/p' "$dir/fixture.config")")
    verdict=$(sed -n 's/^{expect, \([a-z_]*\)}.*/\1/p' "$dir/fixture.config")
    heading=$page_name
    prompt="<a href=\"$REPO_URL/blob/main/trials/ui/$label/prompt.txt\">today's ui prompt</a>, which describes how the page looks"
    [ "$round" = current ] ||
        prompt="<a href=\"$REPO_URL/blob/main/trials/ui/$label/prompt.txt\">the first ui prompt</a>, which said what the page does but not how it looks"
    if grep -q '^{prompt_variant, guided}' "$dir/fixture.config"; then
        heading="$page_name, guided prompt"
        prompt="$prompt, in its guided form: one more paragraph on how to request media playback on an iPhone"
    fi
    # The browser runs 13 checks; the fixture names those a failed page missed.
    if [ "$verdict" = pass ]; then
        result="Passed all 13 browser checks."
    elif [ "$verdict" = ui_failed ]; then
        failed=$(sed -n 's/^{failed_checks, \[\(.*\)\]}.*/\1/p' "$dir/fixture.config" | tr -d ' ' | tr , ' ')
        count=0 why=""
        for check in $failed; do
            count=$((count + 1))
            why="${why:+$why; }$(missing "$check")"
        done
        result="Passed $((13 - count)) of 13 browser checks. Missing: $why."
    else
        result="Verdict: <code>$verdict</code>."
    fi
    mkdir -p "$OUT/demo/ui/$label"
    cp "$dir/reply.txt" "$OUT/demo/ui/$label/index.html"
    cp "$ROOT/_build/pan-demo/modules.js" "$OUT/demo/ui/$label/modules.js"
    cat >> "$GALLERY" <<PAGE
<div class="entry">

### $heading {#$label}

<ul class="credits"><li>Page written by $page_name</li><li>Sound modules written by $MOD_NAME</li></ul>
<p>Prompt: $prompt.</p>
<p>$result <a href="../../doc/ui.html#check-a-page">What the checks cover</a></p>
<p><a href="$label/index.html">Open the page</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/reply.txt">The page, as the model returned it</a> · <a href="$REPO_URL/blob/main/trials/ui/$label/fixture.config">Model, settings and verdict</a> · Sound modules: <a href="$REPO_URL/blob/main/$PAN_DIR/reply.txt">Original</a>, <a href="$REPO_URL/blob/main/$REV_DIR/reply.txt">Reversed</a></p>
<iframe class="preview" src="$label/index.html" title="Demo page written by $heading" sandbox="allow-scripts" allow="autoplay" loading="lazy"></iframe>

</div>

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
    for dir in $dirs; do grep -q '^{expect, pass}' "$dir/fixture.config" && gallery_entry "$dir" "$round"; done
    for dir in $dirs; do grep -q '^{expect, pass}' "$dir/fixture.config" || gallery_entry "$dir" "$round"; done
}

gallery_section current "Today's prompt" \
    "These pages answered the [ui prompt]($REPO_URL/blob/main/prompts/ui.txt) as it is now. It describes how the page looks as well as what it does, after the hand-written [demo](../pan/)."
gallery_section earlier "The first prompt" \
    "These pages answered the [first version of the prompt]($REPO_URL/blob/main/prompts/ui.first.txt), which said what the page does but not how it looks."
pandoc --from gfm+attributes --to html5 --standalone \
    --template "$ROOT/site/template.html" --lua-filter "$ROOT/site/anchors.lua" \
    --metadata source="prompts/ui.txt" --metadata repo="$REPO_URL" \
    --metadata pagetitle="Pages the models wrote" --variable root="../../" \
    --output "$OUT/demo/ui/index.html" "$GALLERY"

# Plain files: no Jekyll processing on GitHub Pages.
touch "$OUT/.nojekyll"
echo "build-site: $OUT"
