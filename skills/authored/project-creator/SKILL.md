---
name: project-creator
description: >-
  Start a repository from nothing: interview, git and forge setup, licenses, .gitignore,
  .envrc, CI and hashpinned workflows. Use when the request is to
  create/scaffold/bootstrap a new project/repository/CLI, from scratch, a new Rust project,
  set up a repo like hashpinner or skillmgr, or set up CI and releases for a brand-new
  repository. It unfolds into workspace, hooks, release (including the first tag and
  published assets) and Playwright/browser-test work as each becomes relevant. Not for
  adding features, CI steps or release targets to an existing repository.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Start a project from nothing

This skill owns the interview, the repository shell, CI and the handoffs between phases.
The Cargo workspace, git hooks, release and browser harness each have their own procedure;
this skill sequences them and does not reimplement them.

Work one phase at a time: at each boundary say the phase sentence and hand over.

Paths beginning `templates/`, `references/` or `scripts/` are relative to the directory
containing this file; shell commands run in the new project or its parent.

## The phase sequence

| # | Say this, verbatim | Leaves behind |
|---|---|---|
| 1 | *(this skill)* | answers, preflight, initial commit |
| 2 | **Scaffold the Cargo workspace and its dendritic Nix flake.** | `Cargo.toml`, `crates/*`, `rust-toolchain.toml`, `justfile`, `README.tpl`, `flake.nix`, `nix/` |
| 3 | **Wire the repository's git hooks.** | `nix/hooks.nix`, hook activation in the devshell |
| 4 | **Set up CI and hashpinning.** | composite actions, CI workflows, hashpinner |
| 5 | **Set up and cut the tag-driven binary release end to end.** | release recipes, release workflow, `nix/binary.nix`, tag, published assets, pinned hashes |
| 6 | **If the project serves a web UI, wire Agentic Playwright and its browser test harness.** | Playwright, browsers, screenshots, e2e CI |
| 7 | **Verify the whole thing.** | a report of what passed and what is left |

The sentence is the routing key. Say it unchanged; paraphrase only in surrounding prose.
If a phase does not apply, say why and skip it — do not invent a variant.

## 1. Interview

Ask one batch, with defaults, and stop until answered. Full wording, per-answer file
consequences and follow-ups are in `references/interview.md`.

| Question | Default |
|---|---|
| Project name (kebab-case; directory, crate and binary name) | *required* |
| One-line description for `flake.nix` and the README | *required* |
| Shape: single binary / library / library + CLI / multi-crate workspace | single binary |
| Names and responsibilities of the crates, if more than one | derived from the project name |
| Does the project serve a web UI? | no |
| Forge: GitHub / Forgejo / both | GitHub |
| Create the remote now, and private or public? | yes, private |
| Make the initial commit? | yes |

A library with no binary does not get a tag-driven release; say so now if that phase will
be skipped.

Never ask about workspace lints, edition, treefmt, conventional commits, lock-check, the
dendritic layout or the MIT/Apache default; announce them once. Discuss license only if
the user raises it.

## 2. Preflight

Run this before writing a file. It reports and never writes:

```bash
bash scripts/preflight.sh example github
```

Hard stops:

- `git config user.name` or `user.email` is empty. Do not invent an identity, not even
  from the directory owner or the GitHub login.
- The target directory exists and is not empty. Stop; ask whether to adopt it as an
  existing repository or to choose a new directory. Never delete or overwrite its files.
- The chosen remote already exists. Stop and ask whether to clone it instead.
- `git`, `nix` or `just` is missing. `cargo` may be missing: the devshell supplies it.
  `gh` is required only when a GitHub remote will be created.

Report the warnings (missing `cargo`, no `tea`, unauthenticated `gh`) and continue.

## 3. Repository shell

```bash
mkdir -p example
cd example
git init -b main
```

Copy from `templates/`, keeping the destinations:

- `.gitignore` — Rust, Nix, dist, editor and OS noise. No `/hk.pkl`.
- `.envrc` — `use flake` plus `watch_file` over `flake.nix` and `nix/*.nix`.
- `LICENSE-MIT`, `LICENSE-APACHE` — verbatim; update only the MIT year.
- `README.md` — stub, replaced once `README.tpl` exists. Keep the title and description;
  do not invest in prose here.

If the user asked for an initial commit:

```bash
git add -A
git commit -m "chore: scaffold repository shell"
```

Create the remote only if the user asked for it, and only after the first commit:

```bash
owner=$(gh api user --jq .login)
gh repo create "$owner/example" --private --source=. --remote=origin --push
```

Use `--public` if that was the answer. Forgejo has no `gh` equivalent; follow
`references/forgejo.md` and let the user create an empty repository, then:

```bash
git remote add origin https://git.example.com/owner/example.git
git push -u origin main
```

Exit check: `git status --short` is clean and `ls -A` shows the shell files.

## 4. Scaffold the Cargo workspace and its dendritic Nix flake.

**Say: "Scaffold the Cargo workspace and its dendritic Nix flake."**

Outcome: a workspace whose members match the interview, a pinned toolchain, the `justfile`
verbs, `README.tpl` with a generated `README.md`, a `flake.nix` of inputs plus
`import-tree ./nix`, and the base `nix/` modules including the crate2nix decision.

Hand over the shape and crate names. Stop when `nix develop -c true` and `just ci` work. Do
not write `Cargo.toml`, `justfile`, `README.tpl` or a base Nix module here.

## 5. Wire the repository's git hooks.

**Say: "Wire the repository's git hooks."**

Outcome: hooks that format on commit, reject a non-conventional message and run the
pre-push checks; installed on devshell entry; a README check and tag guard when their
files exist; `nix flake check` passes offline.

Hand over excluded generated files, secrets, pre-push tests and any database cache. Do not
tune treefmt, edit the `justfile` or rewrite the devshell here.

## 6. Set up CI and hashpinning.

**Say: "Set up CI and hashpinning."**

This phase is owned here. Every action reference below is pinned to a commit and carries
a `# vX.Y.Z, YYYY-MM-DD` comment. Never introduce a moving tag, not even in an example or
a comment.

**Flake input.** Insert one block into `flake.nix`'s `inputs` attrset, following the
file's existing ordering and block style; do not reorder the other inputs:

```nix
    hashpinner = {
      url = "github:sshine/hashpinner";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

Then `nix flake lock`. Do not add `flake-parts` or `treefmt-nix` follows: hashpinner
takes neither.

**Devshell module.** Copy `templates/nix/hashpinner.nix`. It contributes to
`devshells.default.packages`, which flake-parts merges with the devshell module, so no
import list changes. On Linux it uses the published static binary; elsewhere it falls
back to the source build.

**Just recipes.** Append, do not rewrite. Check first with
`grep -nE '^pin(-check)?([ :]|$)' justfile`.

```just
# Pin every action reference, actions/* included, and annotate each with its release
pin *args='':
    hashpinner --pin --no-allow {{args}}

# Fail if a reference is unpinned or a version comment does not match its commit
pin-check:
    hashpinner --check --deep --no-allow
```

`just pin --bump` moves existing pins onto their latest release. `pin-check` needs network
for `--deep`; that is why it is a separate recipe from `just ci`, not a prerequisite.

**Composite actions.** Copy both, keeping their paths:

- `templates/.github/actions/setup-nix/action.yml` — installs Nix and warms the store;
  checkout is the caller's job.
- `templates/.github/actions/checks/action.yml` — one named step per check, including
  `just pin-check`, the guarded crate2nix check and the Nix package build.

If the project has no `lint-nix` recipe or no `Cargo.nix`, remove those steps rather than
leaving a red job; a library-only project also drops `nix build .#default`. Same for Forgejo.

**GitHub workflow.** Copy `templates/.github/workflows/ci.yml`. It triggers on push and
pull request to `main`, checks out, then calls the two composites. Tags are the release
phase's business; keeping the triggers disjoint stops a tag from running checks twice.

**Forgejo workflow.** If that forge was chosen, copy `templates/.forgejo/workflows/ci.yml`
and read `references/forgejo.md` first. The differences that matter: `runs-on: nixos`,
absolute action URLs, no store-cache action on a persistent host, and the same check list
as the GitHub composite. When both forges are chosen, both directories exist, but Forgejo
reads only `.forgejo/` and silently ignores `.github/`, so the lists must be kept identical
by hand.

**Deliberately absent.** No release workflow, artifact matrix, crates.io publish or
`nix/binary.nix`; the next phase adds those and reuses these composites.

Exit check:

```bash
nix develop -c just pin-check
nix develop -c hashpinner --check --deep --no-allow
```

Both must pass with only pinned references reported. On a new repository `--deep` fetches
the action repositories; network is required.

## 7. Set up and cut the tag-driven binary release end to end.

**Say: "Set up and cut the tag-driven binary release end to end."**

Outcome: `check-version`, `dist` and `tag` recipes; a `v*`-triggered release workflow that
reuses the checks above; static musl tarballs with `.sha256` sidecars; an optional
crates.io publish; and `nix/binary.nix` for consumers without Rust.

Hand over whether the crate name is free, whether publishing is enabled, macOS aarch64,
draft or immediate, and the registry-token secret. Do not write a release workflow here,
and do not extend the CI composites with publishing.

**Scaffolding is not a release.** Unless the user says "scaffold only", cut it end to end after main CI is green: tag, watch the release, verify assets, pin hashes, push.

## 8. If the project serves a web UI, wire Agentic Playwright.

**Say: "If the project serves a web UI, wire Agentic Playwright and its browser test harness."**

Outcome: a browser that is the same store path on a developer's machine and in CI, a
throwaway server per run, screenshots a human can open and trust, and a
planner/generator/healer loop for writing and repairing the tests.

Skip it when the answer was no. Do not add a browser, a test runner or a Node toolchain
speculatively.

## 9. Verify the whole thing.

**Say: "Verify the whole thing."**

Run what applies and paste the results into the report:

```bash
nix flake check
nix develop -c just ci
nix develop -c just pin-check
nix develop -c cargo run -- --help
```

For a library with no binary, run `nix develop -c cargo test --doc` instead of `cargo run`.

Then report:

- What passed, by command; what was syntax-checked but not built (YAML, Nix parsing,
  shell syntax).
- What is intentionally absent: the release if phase 5 was skipped, the browser
  harness if there is no web UI.
- What only the integration run can prove: the flake evaluates on a clean machine, CI is
  green on the forge, a tag produces the artifacts.

Do not say the scaffold builds. Say what you ran and what a green CI run must show.

## If this is already present

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

Missing pieces are added in place. Read the whole file first, insert one concern at a time,
keep surrounding comments, and do not reformat or reorder what you are adding to. An
existing `pin-check` with different flags is left alone unless it disagrees with the CI
step, in which case say so and ask. If an edit needs a rewrite to be safe, stop and explain.

## Hard rules

- Every `uses:` in this skill's output is a commit SHA with a version/date comment.
- No workspace lints, treefmt configuration, hook details or release recipes in this
  skill's body. Name the phase outcome and let the matching procedure own the details.
- No claiming a build or a release works from a syntax check.
