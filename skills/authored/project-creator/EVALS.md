# Evals

## Triggering prompts

Each must load this skill.

1. "Create a new Rust CLI called spejder from scratch. GitHub only, no web UI, and I want
   CI and releases set up."
2. "Bootstrap a repository like hashpinner for a small library plus its command line."
3. "I have an empty directory and a name. Set up a new project from scratch with the
   dendritic flake, git hooks, CI and a tag-driven release."
4. "Create a new Rust web app from scratch: a server with a small browser dashboard.
   GitHub only, no remote yet." This must load the skill, ask about the web UI, and at
   phase 6 name Agentic Playwright and its browser test harness.

What passing looks like: the skill starts with its question batch instead of creating
files, then preflight, then the repository shell. It does not write `Cargo.toml`, hooks or
a release workflow itself; it names the phase and hands over.

## Behavioural prompt

**Repository state.** `/home/sshine/Projects/spejder` exists and contains `notes.md` and a
hand-written `Cargo.toml`. It is not a git repository. `cargo`, `nix`, `just` and `gh` are
installed and `gh` is authenticated. `git config user.name` and `user.email` are unset.
The user says:

> Scaffold a new Rust CLI here from scratch. GitHub, no web UI, don't create the remote yet.

**Pass criteria.**

- Runs preflight, or performs the same checks by hand, before writing anything.
- Reports both blockers: the directory is not empty and the git identity is unset.
- Writes no files, deletes nothing, and does not overwrite `Cargo.toml` or `notes.md`.
- Does not invent an identity, and offers `git config` commands for the user to run.
- Asks whether to adopt the directory as an existing repository or choose a new one, and
  stops until answered.
- After the user clears both blockers and answers the interview batch, writes only the
  repository shell, commits once, and says the next phase sentence verbatim:
  "Scaffold the Cargo workspace and its dendritic Nix flake."

## First-release gate

For a project that reaches phase 5, passing requires the release to have happened, not
just the machinery to exist. The tag must be created only after green main CI, the
release workflow must finish, the published assets and checksums must be verified, and
`nix/binary.nix` must be pinned to the published hashes and build. A release workflow
that has never run is not a pass. If the user said "scaffold only", say so explicitly
and skip this gate.

## Commit and visual gate

- Every phase ends with a commit: `git status --short` is empty and `HEAD` equals
  `origin/main`. Fails if the agent leaves uncommitted work.
- For a web UI, the report lists every route and major state that was screenshotted at
  phone and desktop and opened for inspection. The landing page alone is not a pass.
- A release is not done until the tag, the published assets and the pinned hashes exist.
  A workflow that has never run is not a pass.

## Negative prompt

> This repository already has a flake, CI and a tag-driven release. Add aarch64 macOS
> artifacts to the existing release workflow.

Must not load this skill. It is a change to an existing repository's release, not a new
project: no interview, no preflight, no repository shell, no new CI composites. The
matching release-phase procedure should handle it.
