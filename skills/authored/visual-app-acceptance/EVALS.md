# Evals

## Triggering prompts

Each of these must load the skill before any CSS or UI change.

1. "Build a webmail UI with an inbox, a message view, and a Compose page."
2. "Compose and Reply are broken: the text wraps one character per line. Fix it and make
   sure the other subpages are not broken."
3. "Add an end-to-end feature to the existing dashboard and validate it visually."
4. "The mobile header overflows and the search page is blank. Review the UI."

What passing looks like: the agent inventories the routes and states, reproduces the
problem with Playwright, takes a before screenshot, opens the screenshots, fixes the
layout cause, adds geometry regression tests, re-runs the full suite, re-inspects phone
and desktop, and commits the fix.

## Behavioural prompt

**Repository state.** A mock webmail app whose shell is a three-column grid:

```css
.app { grid-template-columns: 232px 6px minmax(0, 1fr); }
```

Split views render a folder splitter in the 6px column. The single-column pages
`/compose`, `/compose?to=...`, `/search`, and `/error` intentionally omit the splitter,
but the shell still renders `<div class="app">` with the three-column grid. The
single-column `<main class="workspace is-single">` is therefore auto-placed into the 6px
splitter column, and its `minmax(0, 1fr)` collapses to 6px, so the text wraps one
character per line. The existing unit tests only assert that the HTML contains "compose"
and the form fields; they pass.

The user says:

> Compose and Reply are broken: the text wraps one character per line. Fix it and make
> sure the other subpages are not broken.

**Pass criteria.**

- Inventories `/`, `/mailbox/:id`, `/message/:id`, `/compose`, a prefilled reply,
  `/search` with results, empty search, error, and both phone and desktop.
- Reproduces with Playwright and keeps a before screenshot.
- Opens the before screenshot and identifies the 6px splitter column (or an equivalent
  root cause) rather than guessing from the source.
- Fixes the layout mode, for example `.app.is-single` with a two-track grid; not padding
  or a magic width.
- Adds a geometry regression test for `/compose` and a prefilled reply: `.app.is-single`,
  no folder splitter, workspace/form widths above the thresholds, no horizontal overflow,
  and the form fields visible.
- Re-runs the full Playwright suite, re-takes phone and desktop screenshots, opens them,
  and checks the split view and one unrelated subpage for regressions.
- Commits the layout fix and the test; tree clean; CI green.
- Does not claim visual correctness from the unit test, HTML string, or DOM presence.

Fails if it only edits CSS without opening a screenshot, only checks the landing page, or
leaves the fix uncommitted.

## Negative prompts

These must not load the skill.

- "Add a database migration and update the SQL schema."
- "Fix a Rust clippy warning in the parser."

The answer should be about the migration or the lint, not routes, screenshots, or
Playwright.
