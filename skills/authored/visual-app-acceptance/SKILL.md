---
name: visual-app-acceptance
description: >-
  Validate a web application visually, not just structurally: inventory every route and
  major state, drive each one with Playwright, screenshot at phone and desktop, open and
  inspect every screenshot, fix layout defects (one-character-per-line text, a pane in a
  splitter column, overflow, clipping, empty panes, mobile header overflow), and add a
  regression test per visual bug. Use whenever building or changing a large visual app,
  web UI, dashboard, inbox, form, compose/reply flow, responsive layout, or when a
  subpage looks broken, text wraps one character per line, content overflows, or the UI
  is only checked by DOM assertions. Applies to a new app and to an end-to-end feature on
  an existing one.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Visual acceptance for web apps

A DOM assertion can pass while the page is visibly broken. The canonical failure is a
single-column compose page placed in a three-column grid (`folders | 6px splitter | main`)
whose splitter element is absent: the main pane lands in the 6px column and every word
wraps one character per line. The HTML is valid, the unit tests pass, and the page is
unusable. Only a screenshot catches it.

This skill is the visual gate. It assumes the app runs under Playwright with stable mock
data. It does not wire the browser; if the browser is not wired yet, do that first.

## When to use

Use it for any page, pane, form, or interactive state that a person will see: a new app,
a new subpage, a compose/reply flow, a search result, an empty or error state, a
responsive layout, or a visual bug report. Use it even when the user says "just add the
page"; a page that has not been looked at is not done.

## The gate

### 1. Inventory every route and major state

Read the router and the views. Write the list down before touching the browser:

- landing / inbox / dashboard
- every folder or top-level view
- a selected message or record
- compose, reply, and any prefilled variant
- search with results, search with no results
- empty, loading, permission-denied, and error states
- phone and desktop widths
- resized or persisted pane widths, if the layout has splitters

A page not in the inventory is a page nobody checked. Add it or say why it is out of
scope.

### 2. Reproduce before fixing

Open the broken state with Playwright, not by reasoning from the source. Take a
before screenshot and keep it. Note the viewport and the URL. If another checkout or
worktree may be serving the same port, use an isolated port; a screenshot from the wrong
tree is worse than no screenshot.

### 3. Drive the real interaction

Click Compose, click Reply, type into the form, submit the search, drag the splitter.
`page.goto` alone misses bugs in the interaction that opens the page. Assert that the
form fields are visible and usable, not just that the route returns 200.

### 4. Screenshot at phone and desktop

Use the app's breakpoints; the house defaults are `390x844` and `1440x900`. Use stable
mock data. Save with descriptive names under `screenshots/` if the repository tracks
them, otherwise a temporary directory, and report the paths.

### 5. Open every screenshot and look at it

Use the image tool. A screenshot you did not open is not evidence. Check:

- text wrapping one character or one word per line
- a pane or form narrower than its content, or in a splitter column
- overflow, clipping, horizontal scroll, overlapping elements
- an empty pane where content should be, or content under the header
- missing buttons, form controls, avatars, counts, or dates
- unreadable contrast, focus states, disabled states
- mobile header or chip-strip overflow
- a fix that breaks the split view or another subpage

If the page looks wrong, fix the cause. Padding or a magic width is not a fix if the
element is in the wrong grid track.

### 6. Assert geometry, not just presence

A unit test that checks `html.contains("compose")` cannot catch a 6px pane. Add a
Playwright assertion for the geometry that failed:

```ts
const workspace = (await page.locator(".workspace").boundingBox())!;
expect(workspace.width).toBeGreaterThan(900);
const form = (await page.locator(".compose-form").boundingBox())!;
expect(form.width).toBeGreaterThan(600);
expect(
    await page.evaluate(
        () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
    ),
).toBe(true);
```

Also assert the state class or layout mode (for example `.app.is-single`), the absence of
a splitter on a single-column page, and the presence of the form fields. Add one
regression test per visual bug; keep it next to the other e2e tests.

### 7. Fix the cause, then re-run and re-open

Inspect the grid/flex tracks, `minmax(0, 1fr)`, splitter columns, `min-width: 0`, and the
class that selects the single-column layout. After the fix:

- run the full Playwright suite, not only the new test
- re-take both screenshots
- open them again and compare with the before screenshot
- check the split view, mobile, and at least one other subpage for regressions

### 8. Commit the fix and the regression test

The visual gate is not done with uncommitted code. Commit the layout fix, the new test,
and any refreshed screenshot that the repository tracks. Push and let the hooks and CI
run. If the repository is dirty with someone else's work, stop and ask; do not bury the
fix among unrelated changes.

## Known traps

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Text wraps one character per line | The pane is in a 6px splitter column or a 1-character width | Inspect the computed grid tracks and the parent's `grid-template-columns` |
| Single-column page is narrow | The shell always reserves a splitter column; the page omits the splitter element | Add a single-column class with a two-track grid |
| Pane collapses to 0 | `minmax(0, 1fr)` inside a zero-width track | Check `boundingBox().width` of the pane and its parent |
| Content overflows horizontally | A fixed width, a long unbroken string, or a missing `min-width: 0` | `scrollWidth > clientWidth`; inspect the narrowest ancestor |
| Empty reading pane | The selected record is not passed to the view, or the pane is hidden at this breakpoint | Open the message URL and check the pane content |
| Mobile header overflows | Too many chips/buttons in one row; no wrap/scroll | Screenshot at 390x844 and check the header |
| Splitter widths reset | Full-page navigation loses in-memory state | Persist widths and test navigation/reload |
| Fix works on desktop but not mobile | The breakpoint override still uses the old track list | Re-check both widths after the fix |

`references/checklist.md` has the full inventory and defect list.
`references/playwright.md` has the screenshot and geometry snippets.

## Definition of done

- Every route/state in the inventory has a screenshot at phone and desktop.
- Every screenshot was opened and inspected with vision.
- No known visual defect remains; the fix addresses the cause.
- A regression test covers each visual bug and the full suite passes.
- The fix and tests are committed; the tree is clean and CI is green.
- The report lists the inventory, screenshot paths, defects, fixes, and anything deferred.
