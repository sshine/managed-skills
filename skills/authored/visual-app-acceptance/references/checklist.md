# Visual acceptance checklist

## 1. Route and state inventory

Fill this in before opening the browser. Read the router and the views; do not guess.

| Route / state | How it is reached | Phone | Desktop | Notes |
| --- | --- | --- | --- | --- |
| `/` or landing | direct | ☐ | ☐ | |
| each folder / top-level view | folder link | ☐ | ☐ | |
| selected message / record | message link | ☐ | ☐ | reading pane content |
| compose | Compose button | ☐ | ☐ | form width, fields |
| reply | Reply button | ☐ | ☐ | prefilled recipient |
| search with results | search form | ☐ | ☐ | filtered list |
| search with no results | impossible query | ☐ | ☐ | empty state |
| error / permission denied | bad path or fixture | ☐ | ☐ | message, not a crash |
| resized panes | drag splitter | ☐ | ☐ | persistence after navigation |
| mobile breakpoint | 390x844 | ☐ | — | header, chips, reading pane |

Add every route the app exposes, including any hidden debug or admin route.

## 2. Defect checklist

### Layout and geometry

- [ ] No pane or form is in a splitter column, a zero-width track, or a 1-character width.
- [ ] No text wraps one character or one word per line.
- [ ] No horizontal scroll: `scrollWidth <= clientWidth` on the page and the main pane.
- [ ] No clipped buttons, avatars, counts, dates, or form controls.
- [ ] No overlapping header, sidebar, list, or reading pane.
- [ ] No empty pane where the selected record should be.
- [ ] Single-column pages (compose, reply, search, error) do not reserve a splitter track.
- [ ] Split panes keep their widths across navigation and reload, if they are resizable.

### Text and content

- [ ] Sender, subject, preview, date, folder counts, and unread/starred markers are present.
- [ ] Long subjects and long sender names wrap or truncate deliberately.
- [ ] The reading pane shows the subject, sender, recipient, date, and body.
- [ ] The compose form shows To, Subject, Body, Send (mock), and the mock-only notice.
- [ ] Empty, error, and loading states say what happened.

### Interaction

- [ ] Compose opens from the header and from the keyboard/focus path.
- [ ] Reply opens with the recipient prefilled.
- [ ] Search submits and the list changes.
- [ ] A splitter drags, clamps, and persists; keyboard arrows work.
- [ ] Focus outlines are visible; disabled controls look disabled.

### Responsive

- [ ] 390x844: header, folder chips, list, and reading pane are all reachable.
- [ ] 1440x900: the three-pane layout uses the available width.
- [ ] The mobile header does not overflow or hide the search/Compose actions.
- [ ] A desktop resize does not leave a stale track list.

## 3. Case study: the Compose pane in a 6px column

The shell was a three-column grid:

```css
.app {
    display: grid;
    grid-template-columns: 232px 6px minmax(0, 1fr);
}
```

Split views rendered a folder splitter in the 6px column. Single-column pages
(`/compose`, reply, search, error) omitted the splitter element, so `<main>` was
auto-placed into the 6px column. Its own `minmax(0, 1fr)` collapsed to 6px, leaving only
the pane's padding; every character wrapped onto its own line.

The fix was a layout mode, not padding:

```css
.app.is-single {
    grid-template-columns: var(--folders-width, 232px) minmax(0, 1fr);
}
```

and the shell renders `<div class="app is-single">` for single-column documents. The
regression test opens `/compose` and a prefilled reply after widening the message list,
asserts `.app.is-single`, asserts no folder splitter, and checks the workspace and form
widths are greater than 900px and 600px. A unit test that only checks for the string
"compose" would have passed while the page was unusable.

## 4. Evidence to keep

- Before screenshot: the broken state, with the URL and viewport in the name.
- After screenshots: phone and desktop, with descriptive names.
- The Playwright test that would have caught the bug.
- The full-suite result, not only the new test.
- A short note of what each screenshot showed and what changed.

## 5. Stop conditions

Stop and ask before:

- committing someone else's uncommitted work;
- changing a shared layout used by pages outside the inventory;
- hiding a pane at a breakpoint without checking that its content is reachable;
- claiming visual correctness from DOM strings, HTML snapshots, or unit tests alone.
