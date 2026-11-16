# Idempotence checks

Check before adding; never rewrite a file because the template differs.

| Artifact | Check |
|---|---|
| Git repository | `git rev-parse --git-dir` |
| Ignore rules | `test -f .gitignore && grep -qx '/target/' .gitignore` |
| Direnv shell | `test -f .envrc && grep -q 'use flake' .envrc` |
| Licenses | `test -f LICENSE-MIT && test -f LICENSE-APACHE` |
| Flake input | `grep -q 'hashpinner' flake.nix` |
| Hashpinner module | `test -f nix/hashpinner.nix` |
| Pin recipes | `grep -qE '^pin-check([ :]|$)' justfile` |
| Composites | `test -f .github/actions/setup-nix/action.yml` |
| Pin step | `grep -q 'pin-check' .github/actions/checks/action.yml` |
| CI workflow | `test -f .github/workflows/ci.yml` |

Missing pieces are added in place. Read the whole file first, insert one concern at a
time, keep surrounding comments, and do not reformat or reorder what you are adding to.
An existing `pin-check` with different flags is left alone unless it disagrees with the
CI step, in which case say so and ask. If an edit needs a rewrite to be safe, stop and
explain.

## Commit hygiene

A phase is not done until its work is committed and pushed. At every boundary:

```bash
git status --short          # must be empty
git rev-parse HEAD origin/main
```

If the tree is dirty with work you did not create, stop and ask; do not bury a phase's
changes among someone else's edits. If the user asked for a local-only repository, the
`origin/main` check is replaced by a clean tree and a recorded commit SHA.
