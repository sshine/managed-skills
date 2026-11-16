# Visual acceptance — <app or feature>

## Inventory

| Route / state | How reached | Phone | Desktop | Notes |
| --- | --- | --- | --- | --- |
| | | ☐ | ☐ | |
| | | ☐ | ☐ | |
| | | ☐ | ☐ | |
| | | ☐ | ☐ | |
| | | ☐ | ☐ | |

Include compose, reply, search-with-results, search-with-no-results, error, and the
mobile breakpoint. A route not listed here was not checked.

## Screenshots

| State | Viewport | Path | Opened? | What it showed |
| --- | --- | --- | --- | --- |
| | 1440x900 | | ☐ | |
| | 390x844 | | ☐ | |

## Defects found

| Defect | State | Cause | Fix | Regression test |
| --- | --- | --- | --- | --- |
| | | | | |

## Verification

- [ ] Full Playwright suite passes, not only the new test.
- [ ] Phone and desktop screenshots re-taken after the fix and opened.
- [ ] Split view, mobile, and one unrelated subpage checked for regressions.
- [ ] Geometry assertions cover the failed width/overflow, not just element presence.
- [ ] Fix and tests committed; tree clean; CI green.

## Deferred

List any route, state, or viewport not checked, and why. "Not checked" is not "passes".
