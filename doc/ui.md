# A demo page written by the model

The DX-Ball demo has two parts: the WebAssembly modules that compute the pan, and the page that moves the ball and plays the beeps. In the `ui` task, the model writes the page too. Read this page to see what the model receives, how a generated page is checked in a browser, what the recorded pages did, and what the checks cannot tell you. The runs below were recorded on 23 and 24 November 2026. [DX-Ball experiment](dx-ball.md) · [Prompt](../prompts/ui.txt) · [Guided prompt](../prompts/ui.guided.txt)

## What the model receives

The prompt describes the demo and fixes the contract a page must keep. The page loads `modules.js`, which supplies the two recorded modules as base64. It gets every pan value by calling `screen_pan(x)` on the selected module. It plays a beep every 200 ms through a `StereoPannerNode` whose pan is the value divided by 500. Every beep is the same in both modes. The controls use fixed element ids (`sound`, `mode-original`, `mode-reversed`, `pause`, `reading`), so that a test can find them. The prompt also asks for three outcomes without saying how to reach them: the page works in Safari on an iPhone with the silent switch on, makes no network request, and fits a phone screen. The reply is saved as `index.html` and opened as it is.

Since 24 November 2026, the prompt also describes how the page looks, after the [hand-written demo](../demo/pan/index.html). It gives the colors for light and dark mode, and the order of the parts: a row of controls with Original and Reversed joined, a stage labelled from 0 to 640 with the reading under the ball, a meter for the stereo position, and a collapsed table that checks the SHA-256 of both modules. The browser checks did not change, so they do not judge whether a page follows that description. The [first version](../prompts/ui.first.txt) of the prompt said what the page does but not how it looks. Each trial keeps the exact prompt it received in its `prompt.txt`.

The guided prompt is the same prompt with one paragraph added under the `sound` button. It says to set `navigator.audioSession.type` to `"playback"` inside the click handler, before creating or resuming the audio context. Print either prompt with:

```sh
bin/wasm-bytes prompt ui
bin/wasm-bytes prompt ui --guided
```

## Check a page

The check needs Node and Chrome or Chromium. Set `NODE` or `CHROME` if they are not where the runner looks. The rest of wasm-bytes needs neither.

```sh
bin/wasm-bytes check ui trials/ui/claude-sonnet-5-5-1/reply.txt
```

```text
  check    ok   sound_on: after one click: audio running, 7 panned beeps in 1.3 s, 200 ms apart
  check    ok   ios_audio: audio session set to playback
  check    ok   pan: 13 beeps, each panned by the selected module's value / 500
  check    ok   uses_module: with stand-in modules returning 250 and -125: original shown and played, reversed shown and played
  check    ok   phone: page width 390 px on a 390 px screen
  verdict  pass
```

A reply that is not an HTML document, such as one inside a code fence, gets `not_html`. Otherwise the checker opens the page in headless Chrome with its sound muted. Before the page's own code runs, it wraps the WebAssembly and Web Audio functions. It then records every `screen_pan` call with the module that answered, and every sound the page starts, with the pan, pitch, loudness, and length the page gave it. Clicks are real mouse events, so the browser applies its usual rules for starting audio. The page then runs a second time with stand-in modules that always return 250 and −125. A page that computes the pan itself shows the wrong numbers there. [Checker](../scripts/ui-check.mjs) · [Runner side](../src/wb_ui.erl)

| Check | What passes |
| --- | --- |
| `loads` | No uncaught error, and both modules are instantiated |
| `animates` | `screen_pan` is called on at least five positions a second, all whole numbers from 0 through 640 |
| `reading` | The `reading` element shows a recent x and the value returned for it |
| `sound_on` | One click on `sound` starts the audio, and beeps arrive about 200 ms apart |
| `ios_audio` | Turning the sound on asks for media playback, through the audio-session API or a playing media element |
| `pan` | Each beep's pan is the selected module's recent value divided by 500 |
| `same_beep` | The beeps have the same pitch, loudness, and length in both modes |
| `switch` | Each mode button selects the module that is called. When paused, switching modes shows the selected module's value for the same x |
| `pause` | `pause` holds the ball, and a second click starts it again |
| `sound_off` | A second click on `sound` stops the beeps |
| `uses_module` | With the stand-in modules, the page shows and plays 250 and −125 |
| `network` | The page requests nothing but itself and `modules.js` |
| `phone` | At 390 px wide, nothing scrolls sideways and every control is on screen |

A page passes when every check passes; otherwise its verdict is `ui_failed`, and the failing checks say why.

Four constructed examples show what the checks catch. `reference` is the hand-written demo host as one file, and it passes. `computes-pan` calculates the pan from x instead of calling the module. Its values are right with the real modules, so only `uses_module` fails. `toggle-off` reads the audio state just after creating it, so on browsers where audio starts at once, the first click turns the sound straight off again, and `sound_on` fails. `code-fence` wraps the page in a Markdown fence and gets `not_html`. [Examples](../examples/ui/)

## What the models wrote

The models answered the prompt in two rounds. In the first, the prompt said what the page does but not how it looks. In the second, it also described the look of the hand-written demo. Each Claude model received each prompt once, through the Claude Code CLI with tools off. A local model, Inkling 2 Mini (`inkling-2-mini:26b-a5b-nvfp4`, through Ollama), received the first prompt and its guided version, then the guided version of the second.

Every page, in both rounds, creates a fresh oscillator for each beep, pans it with a `StereoPannerNode`, and calls `screen_pan` on the selected module for every value. Before publishing, each page was read in full. None makes a network request, uses storage, or evaluates code. You can open each page on the site, where it loads the same recorded modules as the hand-written demo. [Pages the models wrote](https://benoitc.github.io/wasm-bytes/demo/ui/)

### With the look described

On 24 November 2026, the four models received the prompt that describes the look. All four pages pass every check.

| Model | Page | How it keeps the silent switch from muting it |
| --- | --- | --- |
| Claude Sonnet 5.5 | 10,890 bytes | Audio session; on an iPhone without it, plays the beeps through a media element |
| Claude Opus 5.5 | 20,556 bytes | Audio session and a silent looping media element |
| Claude Haiku 5.5 | 12,804 bytes | Audio session only |
| Inkling 2 Mini, guided prompt | 14,886 bytes | Audio session only, as the guided paragraph says |

All four follow the description closely: the colors, the joined Original and Reversed buttons, the stage labelled from 0 to 640 with the two-line reading under the ball, the stereo meter, and the collapsed table, which computes the SHA-256 of each loaded module and compares it with the recorded one. Their headings and opening sentences differ. The checks do not compare the look, so this comes from reading each page and viewing it in a browser. [Sonnet](../trials/ui/claude-sonnet-5-5-2/reply.txt) · [Opus](../trials/ui/claude-opus-5-5-2/reply.txt) · [Haiku](../trials/ui/claude-haiku-5-5-2/reply.txt) · [Inkling](../trials/ui/inkling-2-mini-guided-2/reply.txt)

When Sonnet's page was recorded, the runner gave it `ui_failed`: the `pause` check saw the ball move while paused. The check timed its window from just before its click on Pause. The local model was running on the same Mac, the click arrived late, and the check counted the last frames before the pause. The checks now time each window from the click itself. With that fix, Sonnet's unchanged page passes, and every other recorded page and example keeps its verdict. Its `fixture.config` keeps a note of the first verdict.

### Without the look described

On 23 November 2026, each Claude model received the first version of the prompt once. All three pages passed every check.

| Model | Page | How it keeps the silent switch from muting it |
| --- | --- | --- |
| Claude Sonnet 5.5 | 8,138 bytes | Audio session, a silent looping media element, and a silent sample played inside the tap |
| Claude Opus 5.5 | 15,242 bytes | Audio session, with the silent media element as a fallback when that API is missing |
| Claude Haiku 5.5 | 7,456 bytes | Audio session only |

[Sonnet](../trials/ui/claude-sonnet-5-5-1/reply.txt) · [Opus](../trials/ui/claude-opus-5-5-1/reply.txt) · [Haiku](../trials/ui/claude-haiku-5-5-1/reply.txt)

Inkling received the same prompt once. Its 9,403-byte page passes 12 of the 13 checks. It uses the recorded modules for every value, pans every beep correctly, and its controls work. It never asks for media playback, so `ios_audio` fails. On an iPhone with the silent switch on, its sound would probably stay muted. Its verdict is `ui_failed`. The site lists it with that verdict, among the pages from the first prompt. [Inkling's page](../trials/ui/inkling-2-mini-1/reply.txt)

On 24 November 2026, Inkling received the guided prompt once. Its 12,702-byte page passes all 13 checks. When you turn the sound on, it sets the audio session to `playback`, then creates or resumes the audio context, as the added paragraph says. Like Haiku's page, it has no media-element fallback. The paragraph names the API to call, so this pass shows that Inkling follows the instruction, not that it knows the iPhone rule. With one attempt per prompt, it also cannot separate the effect of the paragraph from the variation between attempts. [Inkling's guided page](../trials/ui/inkling-2-mini-guided-1/reply.txt)

## What the checks cannot tell you

- **Whether you hear it.** The browser plays with its output muted. The checks record what the page asks the browser to play, not what reaches a speaker.
- **Safari on an iPhone.** The checks run in Chrome. `ios_audio` simulates the audio-session API that Safari 17 provides, so a page that uses only that API passes, as Haiku's does. Older iOS needs the media-element fallback, which no check exercises. Hearing a page on a phone is still a manual step.
- **How a page looks.** Apart from fitting a 390 px screen, the checks do not judge the design. Whether a page follows the described look was judged by eye.
- **How often a model succeeds.** Each model made one attempt with each prompt it received.
