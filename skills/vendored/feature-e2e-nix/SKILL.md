---
name: feature-e2e-nix
description: >-
  Deliver a feature end to end in a Nix project: interview once, plan vertical slices,
  implement every stub, add backend integration/property/mock tests, drive the real UI
  with Agentic Playwright, screenshot it at phone and desktop sizes into a temporary
  directory, look at those screenshots and iterate until the visuals are consistent,
  then save the good ones to a delivery directory, commit per feature, and push only
  what the user chose. Use this skill whenever the user asks for an "end-to-end tested
  feature", an "end-to-end validated feature", "implement and validate this feature",
  "ship this feature end to end", or wants a feature implemented and verified in the
  browser rather than only coded. It must first check that Agentic Playwright is wired
  into the flake; if it is not, stop and follow agentic-playwright-nix after asking.
---

# Feature, end to end, with Nix

A feature is done when it works through the real stack, is covered at the backend, has
been looked at on a phone and a desktop, is committed, and the push decision is the
user's. Code that compiles, or a unit test that passes, is not done.

## The three non-negotiables

These exist because a capable model still ships a feature that is technically green and
practically unfinished unless it is told otherwise. Treat them as gates, not advice.

### 1. No stubs left behind

Every handler, branch, endpoint, migration, UI state, error path, and test the plan names
must be implemented. Before claiming done, search the changed files and the new paths for:

- `todo!()`, `unimplemented!()`, `panic!("not implemented")`, `throw new Error("not
  implemented")`, `501 Not Implemented`, `NotImplemented`;
- `TODO`, `FIXME`, `XXX`, `placeholder`, `stub`, `coming soon`, "for now";
- disabled controls with no explanation, empty handlers, `return None` on a path that
  should do work, commented-out assertions;
- tests that are skipped or `#[ignore]`d to hide a failure. An ignored test that needs a
  database is legitimate, but it counts as a test only when you run the ignored suite
  (for example `QR_TEST_DATABASE_URL=… cargo test -- --include-ignored`).

If a stub is intentionally out of scope, say so in the plan and in the final report, and
get the user's agreement. Do not leave it to be discovered.

### 2. Run the real end-to-end path, and keep iterating

Start the actual service and database, exercise the flow through the real router/HTTP API
and the real browser, and keep fixing until that path passes. A unit test with a mocked
store is not an end-to-end test; a `TestDb` integration test through the assembled router
is close, and a browser flow against the running server is the rest.

- Use the project's throwaway e2e server recipe; never the dev database.
- Run the ignored database suite as well as the fast suite.
- Run the Playwright suite against that server.
- If something fails, read the failure, fix it, and run it again. Do not report a known
  failure as done, and do not weaken a test to make it pass.
- "It compiles" is not a checkpoint. Neither is "the endpoint returns 200" if the UI never
  reaches it.

### 3. Take screenshots, then actually look at them

Behavioral assertions do not prove the page looks right. Use Agentic Playwright to open
the real page and capture it, then open the images with the image-reading tool and
describe what you see before declaring success.

- Save working screenshots to a temporary directory while iterating, for example
  `.playwright-mcp/<feature-slug>/` or `/tmp/opencode/<feature-slug>/`. These are allowed
  to be ugly; they are your feedback loop.
- Take at least **390×844 (phone)** and **1440×900 (desktop)**, full page for the flow and
  viewport-only for a modal. Add a landscape/rotated phone shot when orientation matters.
- Look for style consistency with the rest of the app: button heights and padding,
  spacing, type scale, radii, icon size, colours, alignment. A new control that is
  slightly taller, unpadded, or a default browser link is a defect.
- Think beyond the literal request where the interface clearly needs it: empty, loading,
  error, long-text, permission-denied, released/deleted, and modal-open states; tap
  targets; wrapping on a narrow screen; no horizontal scroll.
- If a screenshot is wrong, change the code, retake it, and look again. Keep the failed
  shot if it helps explain the fix.
- After the feature is successful, copy the correct shots to a **delivery directory**:
  `feedback/<YYYY-MM-DD>-<feature-slug>/` if the repository already uses `feedback/`,
  otherwise `delivery/<YYYY-MM-DD>-<feature-slug>/`. Name each by state and viewport
  (`album-phone.png`, `release-modal-phone.png`). Add a short `NOTES.md` saying what each
  shows and what was checked. Never leave review screenshots in `test-results/`.

The detailed checklist and the failure catalogue from real use are in
`references/visual-review.md`.

## Preflight: is Agentic Playwright wired?

Run the sibling skill's check from the repository root:

```sh
bash ~/.claude/skills/agentic-playwright-nix/scripts/check.sh
```

If it exits non-zero, or the Playwright MCP tools are absent and the CLI cannot run a
browser, stop. Explain exactly what is missing and ask:

> Agentic Playwright is not wired into this flake. Should I run
> `agentic-playwright-nix` before we start the feature?

Do not proceed on backend tests alone, and do not claim browser validation you did not do.
If the user agrees, follow `agentic-playwright-nix`, then run the check again. If the MCP
tools are merely missing from the current session but the CLI works, say so explicitly and
use `playwright test`; that is still end-to-end, just not agentic.

## Ask once, at the start

Ask the whole batch in one turn, then write a plan and get agreement before coding.

1. **Behavior and non-goals.** What must the feature do, what must it not change, what is
   explicitly out of scope?
2. **Edge cases.** Empty, duplicate, missing, released, permission-denied, offline, long
   input, concurrent use. Which are in scope?
3. **Data and access.** Migrations, retention, soft deletes, who may see or change what,
   whether existing rows need backfilling.
4. **Visual expectations.** Which screens and states matter; any copy; anything the user
   already dislikes about similar screens.
5. **Test expectations.** Which property, mock, integration and browser tests they expect;
   any suite that is slow or should be skipped locally.
6. **Push policy.** Commit only, or commit and push? If push, which remote(s)? Run
   `git remote -v` and list them; if there is more than one, ask which ones and never
   assume the mirror.
7. **Delivery directory.** Confirm the path for the final screenshots.

Then present a short plan:

```text
Feature:
Non-goals:
Slices:
  1. schema + backend contract + integration tests
  2. UI + empty/error/loading states
  3. browser flow + screenshots
Tests: property …, mock …, integration …, e2e …
Screens: phone/desktop, states …
Commit/push: …
```

## Implement in vertical slices

Each slice should end in something demonstrable, not "the backend is half wired".

- Follow the repository's structure, naming, comment style and error conventions. Read
  the neighbouring code before adding a new pattern.
- Use the project's `just` recipes for build, test, migrate and serve. Do not invent an
  npm toolchain in a Nix project; do not run `npx`.
- Migrations: apply them, regenerate the offline query cache if the project has one
  (Rust/sqlx: `just sqlx-prepare`), and commit both.
- If the codebase has a closed event/kind enum, add the new kind and its exhaustiveness
  test rather than a free-form string.
- Respect the security model: capability cookies, server-side authorization, CSRF where
  relevant, no secrets in logs or serialized config, no client-only validation.
- Progressive enhancement where the app practices it: forms that work without script, and
  an Alpine/JS layer on top.
- Accessibility: real labels, roles and focus states; controls at least 44×44 CSS pixels;
  the page remains usable at 200% zoom.
- Do not rewrite unrelated code or "fix" nearby things silently. Note them instead.

## Test layers

Use the project's preferred libraries; the examples are Rust because that is the concrete
case, but the principle is the same elsewhere.

- **Property-based tests** (`proptest` in Rust, Hypothesis in Python, fast-check in TS)
  for invariants that examples miss: parse/format round trips, coordinate and length
  bounds, pagination, idempotence, normalization. A property test that only repeats one
  example is not a property test.
- **Mock tests** where the boundary is genuinely external: `wiremock`/`httpmock` for HTTP,
  `mockall` for a trait. Prefer the real router and a real scratch database for the
  feature's own path; mocks cannot prove SQL, migrations, constraints or transactions.
- **Backend integration** through the assembled router and a scratch database
  (`TestDb` in this repository): success, validation failure, conflict, not-found,
  authorization, and the row/event left behind. Run the ignored suite explicitly.
- **API tests for rules the UI blocks.** If the browser refuses to submit, test the server
  directly; a rule enforced only in the browser is not enforced.
- **Browser tests** through Agentic Playwright: role and label locators, one property per
  test, names that state the invariant, no `networkidle`, no sleeps except an absence
  check with a comment. Use the planner/generator/healer agents when they are available;
  plans go in `e2e/specs/`, and `e2e/tests/seed.spec.ts` stays as it is.

## The visual gate

1. Start the e2e server through the project's recipe.
2. Use the MCP browser (or the CLI) at 390×844 and 1440×900.
3. Screenshot every key state into the temporary directory: the happy path, the modal,
   the empty state, the error state, and anything the plan named.
4. **Open each image and describe it.** Check the list in `references/visual-review.md`.
   In particular: is the CSS actually applied? Is anything a browser default? Are buttons
   in a row the same height? Does the modal cover the viewport and centre? Does a long
   label wrap? Does the photo fill the width? Is the “×” over the corner, not below?
5. Fix, retake, look again. Compare the new screen against an existing one at the same
   viewport, not against your memory of it.
6. Copy the good shots to the delivery directory. Report both the temporary and delivery
   paths in the final message.

If the app has a cache-first service worker, also verify that the page's asset URLs carry
a content version (`/assets/app.css?v=…`) and that the served CSS contains a rule the new
page depends on. A deploy with unversioned assets serves new markup with the old
stylesheet; the setup skill's cache section explains the fix.

## Quality gates before saying done

Run the project's fast checks first, then the full local set. CI is often 25–35 minutes;
catch failures locally.

- `just fmt` / `just fmt-check`
- `just lint` (clippy with `-D warnings`, or equivalent)
- offline query-cache check (`just sqlx-check` in this workspace)
- `just test` and the ignored database suite (`just test-db` here)
- `just e2e` (all specs, not just the new one)
- `just ci` or the repository's equivalent release build/lock/crate checks
- `git status` — no generated artifacts, no fixture secrets, no stray screenshots in
  `test-results/`

Do not push with a failing check. If a check is genuinely unrelated and already broken,
say so with the failure and ask before proceeding.

## Commits and push

- One meaningful commit per feature, or per agreed slice. Conventional message; tests and
  migrations in the same commit as the code they protect.
- Do not leave work uncommitted at the end.
- Push exactly what the user chose at the start: the named remote(s). If there are two
  remotes and they chose one, push that one. If they chose commit-only, stop after the
  commit and say so.
- Do not push a mirror, a tag, or another branch because it seemed helpful.
- If a push fails, report it; do not rewrite history or force-push.

## Done checklist

- [ ] Every planned path is implemented; no stubs or unexplained placeholders remain.
- [ ] The real server/database path was run; the full flow passes.
- [ ] Property, mock and integration tests cover the backend invariants.
- [ ] The Playwright suite passes, including the new browser flow.
- [ ] Phone and desktop screenshots were taken, opened, described, and iterated.
- [ ] Empty/error/loading/long-text states and both orientations were considered.
- [ ] The correct screenshots are in the delivery directory.
- [ ] Fast checks and the full local suite pass; the tree is clean.
- [ ] Commits exist; the chosen remote(s) were pushed, or commit-only was respected.
- [ ] The final report lists tests, screenshots, commits, push status and residual risks.

## Final report template

```text
Feature:
What changed:
Tests:        <commands and results, including ignored DB and e2e>
Screenshots:  <temporary path> -> <delivery path>
Commit(s):    <hashes>
Push:         <remote(s) pushed, or "commit only">
Residual:     <known gaps, out-of-scope stubs, follow-ups>
```
