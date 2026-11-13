# Looking at the page

Behavioral tests can pass while the render is broken. This happened on the QR app: the
new link card passed its DOM tests and looked like a full-width SVG with inline labels on
a phone, and the release dialog rendered inline in the page because the phone had the
previous deploy's CSS and JavaScript. The fix was not "add a CSS assertion"; it was to
take a screenshot and look at it.

Use this reference during the visual gate of `feature-e2e-nix`.

## Capture

- Phone: **390×844** CSS pixels. This is where spacing, wrapping and tap targets fail.
- Desktop: **1440×900** CSS pixels. This is where a full-width image becomes absurd and a
  reading column becomes necessary.
- Full page for a flow; viewport-only for a modal or a fixed bar.
- Landscape/rotated phone when orientation matters.
- Save working shots to `.playwright-mcp/<feature-slug>/` (usually gitignored) or
  `/tmp/opencode/<feature-slug>/`.
- After the feature works, copy the correct shots to
  `feedback/<YYYY-MM-DD>-<feature-slug>/` (or `delivery/…` if the repo has no `feedback/`)
  and add a short `NOTES.md`.
- Name by state and viewport: `album-phone.png`, `release-modal-phone.png`,
  `chooser-desktop.png`, `empty-phone.png`.

## Look report

Write this before touching a test assertion. It forces the eyes to do the work.

```text
Screenshot: <path>            Viewport: <w x h>            State: <what is on screen>
What I see: <one paragraph, including the obvious>
Compared with: <an existing screen at the same viewport>
Problems: <list, or "none">
Fix: <what I changed>
Retake: <path>
```

## Checklist

### The stylesheet and script actually loaded

- The rendered buttons are the app's buttons, not browser defaults.
- An icon is icon-sized, not the width of the card.
- Headings, blurbs and labels stack; labels sit above their inputs.
- A dialog is an overlay, not inline content in the page.
- A control bar has gaps between its controls, not `ManageLocation`.
- If the app has a service worker, the `<link rel="stylesheet">` and `<script src>` URLs
  carry a content version (`?v=…`) and the server serves that version. An unversioned
  cache-first asset is a deploy waiting to show yesterday's layout.

### Consistency with the rest of the app

- Same type scale, line height, spacing scale, corner radius, colours and icon stroke.
- Buttons in one row have the same height and vertical alignment, even when one is
  primary and one is secondary.
- Primary/secondary/destructive treatments mean the same thing as on existing screens.
- A new control does not introduce a second visual language.

### Mobile

- `document.documentElement.scrollWidth <= clientWidth` (no horizontal scroll).
- Text wraps instead of overflowing; long titles, addresses, URLs and locations included.
- Tap targets are at least 44×44 CSS pixels and not crowded.
- The sticky bar does not hide behind a notch; the dialog is reachable and closable.
- Rotating the phone reflows the content rather than clipping it.
- The modal backdrop covers the viewport, and the dialog is centred in it.

### States beyond the request

- Empty, loading, error, permission-denied, long input, duplicate, deleted/released.
- Open and closed modal; after reload; after a second visit.
- Keyboard focus and a visible focus ring; Escape closes a dialog where the framework
  expects it.
- A second photo/row/item: does the layout still work, or only at count = 1?

### Measured layout

Prefer bounding boxes to eyeballing where a property matters:

- an image is the content width (viewport minus the page's horizontal padding), ±1px;
- two buttons in a row share `y` and `height`, ±1px;
- the modal backdrop is exactly the viewport, and the dialog's centre is the viewport's
  centre, ±2px;
- a control that should be over a corner is inside the image's top-right, not below it;
- a tile's height equals its image's height (no extra in-flow button strip).

## Failure catalogue

| What you see | What it usually is | Fix |
| --- | --- | --- |
| Full-width SVG, labels and inputs on one line, full-width submit button | New markup with the previous CSS: an inline `<span>` ignores `width`, the card grid never applied | Content-version the asset URLs and bump the service-worker cache; confirm the CSS contains the new rules |
| Dialog visible inline, page below it, control links unspaced | The previous JS and CSS: the component that owns the dialog did not load, and the bar's flex rules are absent | Same cache fix; render the dialog from a template so a missing component cannot leak it |
| Dialog fixed to the top bar instead of the viewport | An ancestor with `backdrop-filter`, `filter`, `transform` or `will-change` is the containing block for `position: fixed` | Move the dialog out of that ancestor (a sibling, sharing the Alpine scope) |
| Delete “×” in a beige strip below the photo | The JS button has `class="tile-delete"`, but the rule targets `.tile-delete button` | Position the button itself; use a selector shared with the no-script form |
| Capture buttons differ in height or sit low | The labels have different padding and are inline | Make the labels flex items in one row and give both spans the same min-height/padding |
| Photo is a small square instead of a full-width row | The old grid still has `repeat(auto-fill, minmax(8rem, 1fr))` and a square aspect ratio | The new CSS must be loaded; check the computed `grid-template-columns` and `img` width |
| A photo appears before its upload lands, then vanishes on navigation | The pending tile is optimistic; navigating away aborts the request | Wait for a non-pending tile in the test before leaving the page |
| Modal is off-centre only on mobile | The backdrop is sized to a parent, not the viewport | Assert the backdrop box equals the viewport; move the dialog to the body-level scope |

## When the app has a service worker

The HTML is usually network-only while `/assets/*` is cache-first. That combination is
only safe if the asset URL changes with the bytes. Check:

1. The page's stylesheet and scripts have `?v=<content-version>`.
2. The version changes when the file changes (hash the bytes, do not hand-bump a number).
3. Versioned responses are `immutable`; the worker itself is `no-cache`.
4. The worker does not precache unversioned asset URLs; old caches are dropped when the
   worker's cache version changes.
5. The manifest icon carries the same version.

If any of those is false, stop and use the cache section of `agentic-playwright-nix`.
Otherwise the next deploy will look like a CSS bug that cannot be reproduced locally.

## When to stop

Stop and ask, rather than guess, if:

- the screenshot needs a product or copy decision (not a layout fix);
- the only way to make the screenshot pass is to hide content or weaken an assertion;
- the visual problem is a pre-existing fault outside the feature's scope;
- the MCP tools are absent and no browser can be driven in this session. Say so; do not
  claim visual validation.
