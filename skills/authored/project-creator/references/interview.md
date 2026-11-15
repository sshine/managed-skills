# Interview

One message, one batch, then stop. The user may answer with a list, "defaults", or a
correction; do not re-ask what a default already covers.

Ask only for what cannot be inferred from the directory or the forge. If a directory was
named on the command line, use it as the project name.

## The batch

> Before I create anything, answer these in one go. Defaults are in brackets; say
> "defaults" to accept the rest.
>
> 1. **Project name**, kebab-case. It becomes the directory, the Cargo package and the
>    binary name. [required]
> 2. **One-line description**, used in `flake.nix` and the README. [required]
> 3. **Shape**: single binary, library, library + CLI, or a workspace with several
>    crates. [single binary]
> 4. If more than one crate: **crate names and responsibilities**, and which ones are
>    published. [derived: `example-core`, `example-cli`]
> 5. Does the project serve a **web UI**? [no]
> 6. **Forge**: GitHub, Forgejo, or both. [GitHub]
> 7. **Create the remote now**, and private or public? [yes, private]
> 8. **Make the initial commit** now, or leave the tree dirty? [yes]
> 9. Forgejo only: **instance URL and owner/repo**. [no remote]

Question 4 only exists when question 3 asks for more than one crate. Question 9 only
exists when question 6 includes Forgejo. Do not ask a question whose answer is already
in the repository: an existing `Cargo.toml` answers 3 and 4, an existing `origin` answers
7, and a `flake.nix` means this is not a new project.

## What each answer changes

| Answer | Files and steps affected |
|---|---|
| Name | directory, `Cargo.toml` package names, binary name, `flake.nix` description, README title |
| Description | `flake.nix` `description`, README stub, `README.tpl` later |
| Shape | `crates/*`, `[workspace] members`, whether a `packages.default` binary exists, whether phase 5 applies |
| Crate names | `crates/*/Cargo.toml`, `[workspace.dependencies]`, README section, release package list |
| Web UI | phase 8 only; no files in the shell or CI |
| Forge | `.github/` vs `.forgejo/` vs both; whether `gh` is required in preflight |
| Remote | nothing on disk; a `git remote` and possibly a push |
| Initial commit | whether the shell ends with a commit or a dirty tree |
| Forgejo URL | `git remote add origin`, release secrets later |

Say which of these a non-default answer changes when it is not obvious. "Both forges"
means two CI files that must be kept identical; say that out loud.

## Defaults worth stating, not asking

- License: `MIT OR Apache-2.0`, with both files at the root. Mention it only if the user
  asks; never make it a question.
- Workspace lints, edition 2024, resolver 2, treefmt, conventional commits, lock-check,
  the dendritic `nix/` layout: fixed by the house style. Announce, do not ask.
- Private remote: the safe default. Public is a one-word answer away.

## Follow-ups

Ask at most one follow-up round, and only for a contradiction:

- The name is not a valid crate name (uppercase, underscore, leading digit). Propose the
  kebab-case form and ask which spelling the user wants for the binary.
- The directory exists and is non-empty. Ask "adopt this directory as an existing
  repository, or choose a new name?" and write nothing until answered.
- The remote exists. Ask "clone it instead, or pick another name?"
- `gh` is unauthenticated and the user wants a GitHub remote. Ask them to run
  `gh auth login`, or to accept a local-only repository.
- Forgejo was chosen but no instance URL was given. Ask for it before adding a remote;
  the repository shell itself does not need it.

## Stop conditions

Do not proceed to preflight with an unanswered name, shape or forge. Do not invent a git
identity, a forge owner, a Forgejo host, or a license the user did not ask for.

If the user says "just make it", use every default, state them in one line, and continue.
