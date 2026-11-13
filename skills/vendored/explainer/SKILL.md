---
name: explainer
description: Produce a narrated, animated explainer video from a topic — manuscript, local Kokoro speech, seekable HTML/CSS scenes captured frame by frame, muxed to mp4 — or publish the same scenes as an interactive explainer page on a website, played live with the narration as its clock. Widescreen or vertical for mobile, and narrated in English, Mandarin or any other language Kokoro speaks. Use when asked to make an explainer video or explainer page, embed an explainer in a blog or site, animate a concept, turn a project or README into a narrated video, or add a scene to an existing one. Runs offline on x86_64-linux from a pinned Nix flake; no cloud, no API keys.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
user-invocable: true
---

# explainer — narrated animated explainers, as video or as a page

A video is a **manuscript** plus one **HTML page per scene**. Kokoro speaks the
manuscript locally; each page is a pure function of a virtual clock, so it can
be screenshotted frame by frame and muxed with its own narration.

Everything runs in one workspace whose tools are vendored once by a Nix flake.
Individual videos are subdirectories of it:

```
<workspace>/            flake.nix  nix/  lib/  Justfile  template/
  <video-slug>/
    script.json         the manuscript — the single source of truth
    scenes/<id>.html    one page per scene
    out/                narration, clips, contact sheets, the finished mp4
```

## 0. Find the workspace first

The default workspace is `~/Projects/videos`. Before anything else:

- If `~/Projects/videos` exists, work there.
- Otherwise, if the current directory already holds `flake.nix` and `lib/capture.mjs`, it is a workspace; work there.
- Otherwise **ask the user where the workspace should go**, offering `~/Projects/videos`. If they name the current directory and its name does not read like a video workspace, say what will be written into it and confirm before writing anything.

Install or refresh the tooling with `setup.sh`, which sits next to this
SKILL.md. It replaces `flake.nix`, `nix/`, `lib/`, `Justfile`, `template/` and
`.gitignore`, and touches no existing video's sources, so it is also how the
workspace picks up a newer version of the skill:

```bash
bash <this-skill-directory>/setup.sh ~/Projects/videos
cd ~/Projects/videos && nix develop     # chromium, ffmpeg, node, Kokoro
```

Every recipe takes the video's directory name as its first argument. Start one
with `just new <slug>`.

The tooling is improved while making real videos, so a workspace can end up
ahead of the skill it came from. `just skill-diff` shows what has moved and
`just skill-push` copies it back, which is what keeps the next machine from
installing a stale copy.

## 1. Write the manuscript

`<slug>/script.json` owns the voice, the frame rate, the resolution, the theme,
the scene order and every word spoken.

```json
{ "id": "s2_auth", "title": "On-screen title",
  "narration": "What the voice says. Natural, tight, about 2.5 words a second.",
  "tts_text": "Optional respelling, for pronunciation only.",
  "visual": "What animates, beat by beat. This is the storyboard for stage 3." }
```

Ids look like `s<n>_slug`. Narration usually runs 15–25s per scene. `tts_text`
changes only what is spoken; `narration` stays the reader-facing text. Themes
are `light` (default) and `dark`, set as `.meta.theme`.

**Shape.** `.meta.resolution` is the output; `.meta.canvas` is the coordinate
system the pages are authored against, and the two must share an aspect ratio.
Leaving `canvas` at the 1920x1080 default and setting `resolution` smaller
renders a cheap preview of the same layout. For a vertical video set both to
`[1080, 1920]`, so that authoring coordinates are output pixels.

**Language.** `.meta.voice` carries it: Kokoro names a voice for the language
it speaks, and `lib/tts.py` turns that first letter into espeak's code, so a
`z` voice such as `zm_yunyang` is phonemized as Mandarin with nothing else to
set. `.meta.lang` overrides when espeak wants a different variant. `just
voices` lists them all.

```bash
just check <slug>        # manuscript shape, and that every scene has a page
just estimate <slug>     # how long each scene will run, without synthesizing
```

`just estimate` costs nothing and answers the question you actually have while
writing: is this scene the right length, and is the whole thing the length you
promised. It reads a measured speaking rate per voice from
`lib/voice-pace.json`; rates vary widely, so the same script runs 36s in
`am_eric` and 61s in `af_nicole`, which whispers. Trust it to about 1% on the
total and 5% on a scene. Respellings are its blind spot: `M C P` is five
characters and three spoken letter names, so a scene full of them runs long.
Rewrite against the estimate until the numbers look right, then synthesize.

## 2. Speak it — narration sets every scene's length

```bash
just audio <slug>              # all scenes; unchanged ones are skipped
just audio <slug> s2_auth      # just these
just audition <slug>           # play each clip and read along
```

`just audio` writes `out/audio/<id>.wav` and `<id>.dur`, and **`<id>.dur` is
what sizes the visuals** — the clip is the narration plus 0.8s. Render to that,
not to a guess, or speech and picture drift apart.

**Stop at `just audition` and get the user's approval of pronunciation and
pacing.** If a word comes out wrong, set `tts_text`, rerun `just audio <id>`,
audition again. A clip that played is not a clip that was approved. Where a
voice speaks a language you cannot judge by ear, say so and ask; do not ship a
pronunciation nobody has checked.

```bash
just cue <slug>                # where the voice reaches each sentence
just cue <slug> s2_auth
```

`just cue` spreads the measured clip across its sentences by character count
and prints the millisecond each one starts. **Fit every beat to its output.**
An animation timed by guesswork lands half a sentence from where it belongs,
and the error is invisible in a contact sheet and obvious on playback.

## 3. Build the scene pages

Copy `template/scene.html` to `<slug>/scenes/<id>.html` and realize that
scene's `visual`. The skeleton is fixed: `lib/scene.css` then `lib/clock.js`
are the first two `<head>` tags, then `lib/anim.js`. `<div class="stage">` is a
canvas of `.meta.canvas` pixels that scales to the output resolution; place
things with `left`/`top` in px, start animated ones with class `hidden0`.

### The one rule: the virtual-clock contract

A scene page is a **pure function of `?t=<ms>`**. It reads `window.T` and
renders that instant. **Never** use `Date.now()`, `setInterval` or
`requestAnimationFrame` for animation *state*.

Build and query the DOM once, at load. Assign `window.render` and put every
T-dependent mutation inside it, setting complete state on each call — never
appending, never latching a class. The capturer loads the page once and seeks,
forward or backward, so a page that carries state between calls renders wrong.

`lib/clock.js` gives you `window.T`, `seg(t0,t1)`, `fadeWin(t0,t1)`, `lerp`,
`easeInOut`, `clamp`. `lib/anim.js` builds the vocabulary on top:

- `enter(el,t0)` / `pop(el,t0)` — fade-and-rise, scale-pop
- `fadeIn` / `fadeOut` / `showWin(el,t0,t1)` — visible only inside a window
- `pulse(el,t0)` — one-shot glow ring
- `draw(pathEl,t0,dur)` — SVG stroke draw-on
- `typeCmd(el,cmd,t0)` — deterministic typewriter; `cmd` is a string or
  `[{t:"text", c:"cssClass"}]` spans for colour. Returns the ms it finishes, so
  the next beat chains off it.
- `revealLines(el,t0)` — stagger-reveal child lines
- `caretOn()` — 2 Hz blink derived from T

Helpers take bare element ids: `enter("hdr", 300)`, not `"#hdr"`.

### Look at it while you build

```bash
just peek <slug> s2_auth 0 4000 9000 14000
```

Three or four instants, straight to PNG. **Read the images.** Overlaps,
off-canvas elements, wire anchors that no longer meet their boxes, beats that
fire too early — all of it shows up here in seconds. This loop is how the good
scenes get made; do not wait for a full render to find out.

## 4. Render, look, assemble

```bash
just render <slug>             # all scenes, in parallel
just render <slug> s2_auth     # iterate on one
just review <slug>             # six-frame contact sheets per scene
just assemble <slug>           # -> out/<slug>.mp4
just play <slug>
```

`just build <slug>` runs check, audio, render and assemble in order.

**Look at every contact sheet.** They prove frames came out, nothing more —
not that the scene is clear, correctly timed, or says what the narration says.
Evenly spaced samples also miss short beats, so **watch the whole cut before
calling it done**, and get the user's approval.

`just assemble` ends with one cheap probe: stream count, codec, resolution and
frame rate. It is a shape check, not a judgement.

## 5. Or publish it as an explainer page

The same scene pages can play live in a browser instead of being captured.
`lib/page/player.js` loads every scene in an iframe and drives each one through
`window.hfSeek`, with the narration as the clock. Viewers pause on any frame,
scrub, jump between chapters, and click any sentence of the transcript.

Steps 1 to 3 are unchanged: write the manuscript, speak it, build the scenes.
`just render` and `just assemble` are not needed for a page.

### Ask before building

Ask whether the user wants a video, a page, or both. For a page, ask:

- **Where is the site?** Do not assume a path. Look for a site repository near
  the user's projects, read its README and git log, and confirm the one you
  found before writing into it.
- **A page of its own, or embedded in an existing page?** If embedded, which
  page, and where in it.
- **Its own look, or a natural page of the site?** Its own look keeps the
  colours of `lib/scene.css`. A natural page restyles the scenes to the site's
  palette and typeface, and lets the player inherit the site's type and colour.
- **Should the transcript be shown?** The default is yes: it is the page's
  readable text, and it works without JavaScript.

### Find out what the site is

Identify the site before deciding where files go:

| Found                                   | Site                     |
|-----------------------------------------|--------------------------|
| `hugo.toml`, `config.toml` + `content/` | Hugo                     |
| `_config.yml` + `_posts/`               | Jekyll                   |
| `astro.config.*`                        | Astro                    |
| `.eleventy.js`, `eleventy.config.*`     | Eleventy                 |
| `zola.toml`, `config.toml` + `templates/` | Zola                   |
| `next.config.*`, Django, Rails, …       | a dynamic backend        |

Then find where static files are served from and what the site already has for
embedding: shortcodes, partials, components, raw-HTML passthrough. Use the
site's own abstractions. Look for earlier explainers first (`grep -r
explainer`); if the site already has an integration, reuse it as it is.

### Export

```bash
just page <slug>                                   # -> <slug>/out/page/
just page-serve <slug>                             # try it on :8123
just page <slug> <dest-dir> --css <site-theme.css> # into the site
```

The export is one self-contained directory: `manifest.json` (scene start
times, chapter titles, transcript cues), `narration.mp3`, `player.js`,
`player.css`, `index.html` (the explainer on a page of its own), `lib/`, and
`scenes/`. Copy it as a whole; every path inside it is relative. The page runs
exactly as long as the video would.

`<dest-dir>` is replaced wholesale on every export, so it is refused unless it
is empty or an earlier export.

### Embed

A page of its own needs nothing more than the exported directory: serve
`index.html`. To embed the player in a page, the page needs:

```html
<link rel="stylesheet" href="<dir>/player.css">
<script defer src="<dir>/player.js"></script>
<div class="explainer" data-manifest="<dir>/manifest.json"></div>
```

With no transcript in the page, `player.js` builds one inside that element. A
site that renders its own puts it inside the element, or anywhere as
`.explainer-transcript[data-manifest="<same url>"]`, using the markup from
`buildTranscript` in `player.js`: chapters as `.explainer-chapter`, sentences as
`.explainer-cue[data-at=<ms>]`. Render it server-side from `manifest.json`
where the site can, so the text is in the HTML.

`player.css` inherits font and colour and reads its few colours from
`--explainer-accent`, `--explainer-track`, `--explainer-rule`,
`--explainer-mark` and `--explainer-frame`. A site restyles it by setting those
on `.explainer`. It loads after the site's stylesheet, so site rules need a
more specific selector.

### A natural page: restyle the scenes

Write a stylesheet that sets the variables of `lib/scene.css` to the site's
palette and type, under `:root, :root[data-theme]` so it beats both built-in
themes. Square off radii and drop shadows if the site is flat. Keep it in the
site repository, beside its other assets, so the next explainer finds it, and
copy it into the video directory with `.meta.stylesheet` set to its name.
`just peek` then shows the scenes as the site will, and `just page --css`
copies it into the export as `lib/theme.css`.

Author the scenes against that look from the start: a site typeface is often
wider than Inter, and the system's fallback for it wider still. Peek with it.

### Check it in the site

Build the site and open the page in a browser, at desktop and phone widths:

- the poster shows the first scene, and play starts the narration,
- the scrubber and the transcript seek, and the highlighted sentence follows,
- the page appears wherever that kind of content is listed on the site.

The audio has to be seekable. A server without range requests cannot seek an
mp3; the player then fetches it whole instead, so it still works, but
`python3 -m http.server` is such a server and is not representative.

## Gotchas

- **Rerender after any visual change.** Nothing detects that a clip predates an
  edit to its page, `lib/scene.css` or an asset. Change a scene, `just render
  <slug> <id>` before reviewing or assembling.
- **Estimate before you synthesize, measure before you render.** `just estimate`
  is for shaping the manuscript; once narration exists, every clip is sized from
  `out/audio/<id>.dur`, never from the estimate.
- **Speaking rate is a property of the voice, and of the language.** Changing
  `.meta.voice` changes every scene's length by up to a factor of two, so
  re-estimate and re-cue after doing it. Translating is a bigger move still:
  the same script runs about a quarter shorter in Mandarin than in English, so
  every beat in every scene has to be refitted, not nudged.
- **A new language needs its pace measured once.** `just pace <prefix>` fits
  the voices of one family and merges them in, leaving the others alone.
  Without an entry `just estimate` refuses, which blocks nothing: beats come
  from `just cue` on real audio either way.
- **`chars()` prices every character the same.** In a Mandarin script a run of
  Latin text, a product name or an initialism, is counted at the hanzi rate and
  the estimate runs long. It is a shaping tool, not a measurement.
- **Absolute positions drift.** An SVG wire drawn to `M900 740` has to match the
  real px box of what it points at. Move a panel, move its anchors; `just peek`
  catches it immediately.
- **`white-space: pre`** can double-render whitespace runs. For terminal
  alignment use explicit spans and margins.
- **Render one video at a time.** `just render` already fans out across scenes
  and will use a third of the cores; two videos at once just thrash.
- **Check pronunciation against espeak, not against memory.**
  `espeak-ng -v en-us -q --ipa "with A.I."` prints what it will actually say.
  `A I` comes out `ɐ ˈaɪ`, "uh-eye"; `A.I.` comes out `ˌeɪˈaɪ`. One command
  settles an argument that listening repeatedly will not.
