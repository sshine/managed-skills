---
name: nix-git-hooks
description: >-
  Wire a repository's git hooks with hk-nix: treefmt on pre-commit,
  conventional commits on commit-msg, and clippy, deadnix, lock-check and a
  README regeneration hook on pre-push, plus a release-tag guard,
  secret scanning, hashpinned-workflow and actionlint checks, and a sandbox-safe
  checks.hk derivation. Use when asked to wire the git hooks, add hk-nix or
  treefmt-nix to a flake, set up pre-commit, pre-push or commit-msg, enforce
  conventional commits, regenerate README.md from README.tpl, guard a v* tag
  against Cargo.toml, scan for secrets, or when hooks are slow/noisy/missing,
  get bypassed with --no-verify, fire outside the devshell, or `nix flake check`
  fails in the hook runner.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Git hooks that stay fast

A hook is a latency budget. `pre-commit` runs on every commit, so it must be
instant, and it is the only hook allowed to rewrite the tree. `commit-msg` must
be instant too. `pre-push` may take seconds and is where anything that reads the
whole workspace belongs. A five-second pre-commit hook teaches people to type
`--no-verify`, and then no hook runs at all. Decide placement before you decide
the command.

This skill assumes [hk-nix][hk-nix] over [hk][hk], with formatting owned by
[treefmt-nix][treefmt-nix]. hk-nix renders the hook configuration from Nix, pins
every tool by `/nix/store` path, and installs the hooks from the devshell.

[hk-nix]: https://github.com/nix-tools/hk-nix
[hk]: https://github.com/jdx/hk
[treefmt-nix]: https://github.com/numtide/treefmt-nix

## If this is already present

```bash
grep -n "hk-nix" flake.nix 2>/dev/null
grep -rn "hk-nix.settings\|hk-nix.shellHook\|hk-nix.package\|hk-nix.hk" nix/ 2>/dev/null
grep -rn "hk.pkl" .gitignore nix/ 2>/dev/null
```

- If `nix/hooks.nix` already imports `inputs.hk-nix.flakeModules.default`, do not
  write a second hooks module. Add only the steps and settings that are missing,
  and keep the existing commands and comments.
- If the input and module are absent, add them; this skill owns both.
- A comment saying the generated `hk.pkl` is symlinked into the tree and ignored
  is stale. Current hk-nix bakes the config into the `hk` binary as `HK_FILE`,
  so no `hk.pkl` is written and there is nothing to ignore. Correct the comment;
  leave a stray `.gitignore` line alone unless the user asks.
- Never rewrite `justfile`, `nix/devshell.nix`, `flake.nix` or `nix/packages.nix`
  wholesale. Add the input, the devshell package, the startup line and the
  settings; leave the rest of each file untouched.

## Interview

Ask in one batch and stop until answered. Defaults are in the table. Say which
files an answer changes. Infer the rest from the tree: `README.tpl`, a committed
`Cargo.nix`, the languages present, `.sops.yaml`, `.betterleaks.toml`, and the
forge workflow directories.

| Question | Default | What it changes |
| --- | --- | --- |
| Does the project handle secrets, and in which files? | none | `betterleaks` + `gitleaks` globs on pre-commit, `sops-rekey` when `.sops.yaml` exists |
| Are there GitHub or Forgejo workflows? | GitHub if `.github/` exists | `pin-check` and `actionlint` on pre-push; `--deep` in CI |
| Run the unit test suite on pre-push? | no | a `test` step; skip integration tests unless they are seconds |
| Run `nix flake check` on pre-push? | no | a `flake-check` step, or the cheaper `eval-gates` |
| Is there a database or a sqlx offline cache? | no | `sqlx-prepared`, conditional on `DATABASE_URL`, and `sqlx-offline` |
| Which generated files must be excluded? | `Cargo.nix` if committed | `settings.exclude` and the cargo-nix step |
| Install hooks automatically on devshell entry? | yes | `shellHook = config.hk-nix.shellHook` |

Do not ask about treefmt, conventional commits, the lock check or deadnix.
Those are invariants and are already in the baseline.

## Placement model

| Hook | Budget | May rewrite? | Belongs here |
| --- | --- | --- | --- |
| `pre-commit` | about a second | yes: `fix = true`, `stash = "git"` | treefmt; secret scanning, because a leaked secret caught one hook later is already in history |
| `commit-msg` | instant | no | conventional commits |
| `pre-push` | seconds | no, except a reported fix for manual repair | deadnix, clippy, lock-check, README regeneration, tag-version guard, pin-check, doc build, sqlx, hermetic-asset guard |

Rules that follow from the budget:

- Whole-workspace work never goes on pre-commit. Generators and clippy read the
  workspace and are pre-push.
- `stash = "git"` is not optional with `fix = true`: without it a formatter
  rewrites the whole file and a partial `git add -p` is lost.
- Anything needing network, a Cargo dependency closure or a private key is not
  sandbox-safe; keep it out of `checks.hk` and put it in pre-push or CI.
- Two hooks that both rewrite the same file fight forever. Pipe one generator
  into the other instead of diffing raw output (see the README hook below).

## Baseline

Copy `templates/nix/hooks.nix` to `nix/hooks.nix`. It contains:

- `pre-commit`: treefmt with `fix = true`, `stash = "git"`, and the absolute
  `config.treefmt.build.wrapper`; `check` uses `--fail-on-change --no-cache` so
  it works read-only in the `nix flake check` sandbox.
- `commit-msg`: `config.hk-nix.builtins.check_conventional_commit`, which hk runs
  itself, so nothing is pinned.
- `pre-push`: deadnix on `*.nix`; `cargo clippy --all-targets --all-features --
  -D warnings`; `cargo metadata --locked --format-version 1 > /dev/null`; the
  README regeneration step when `README.tpl` exists; and the tag-version guard.
- The tag-version guard reads `{{hook_stdin}}`, handles only `refs/tags/v*`,
  skips deletions (all-zero local sha), and reads the version out of the tagged
  commit with `git show <sha>:Cargo.toml`, never the working tree.

Then adapt:

- `readmeArgs`: `--project-root crates/example --input crates/example/src/main.rs
  --template README.tpl`. cargo-readme 3.4.1 resolves `--input` and `--template`
  against the working directory, which is the repository root when the hook runs,
  so both are root-relative; `--project-root` alone selects the member's manifest.
  The hook reads the generator from `config.packages.cargo-readme`, defined in
  `nix/cargo-readme.nix`; when that module is absent, add the input and file from
  `references/activation.md` first. When there is no `README.tpl`, delete the
  `readme` step and the four let bindings it uses (`readmeArgs`, `cargo-readme`,
  `mdformat`, `readme`), or deadnix reports them as unused bindings.
- The tag-version `sed` reads `[workspace.package]`. If the version lives in
  `[package]`, adjust the range or the guard reports every tag as wrong.
- Replace `example` in the readme paths; the guard itself has no project name.
- For a non-Rust project, keep treefmt and commit-msg and take the language
  steps from `references/catalogue.md` instead of the Rust set. Drop the
  tag-version step unless you point it at that project's version source:
  `git show <sha>:Cargo.toml` fails under `set -e`, and a hook that rejects every
  tag is worse than no hook.

The README hook is the one people get wrong. `cargo-readme` emits Markdown that
`mdformat` immediately rewrites, moving link reference definitions to the end,
so the raw output never equals the committed `README.md`. Pipe the generator
through *treefmt's own* mdformat, taken from
`config.treefmt.settings.formatter.mdformat.command`, so the generator and the
pre-commit formatter share one fixpoint.

## Select project-specific hooks

Add only what the repository actually needs. The full row-per-example catalogue,
with pins and gotchas, is `references/catalogue.md`.

| Signal | Add | Where |
| --- | --- | --- |
| Secrets in the tree | `betterleaks` with `--redact`, plus the `gitleaks` builtin | pre-commit |
| `.sops.yaml` | `sops-rekey` on `.sops.yaml` and `secrets/*.yaml` | pre-commit; needs the age key |
| GitHub/Forgejo workflows | `pin-check` (`hashpinner --check`), `actionlint` builtin | pre-push; `--deep --no-allow` in CI |
| Committed `Cargo.nix` | `settings.exclude = [ "Cargo.nix" ]`, `cargo-nix --check` | every hook, and pre-push |
| sqlx query cache | `sqlx-prepared` (only when `DATABASE_URL` is set) and `sqlx-offline` | pre-push |
| `asset!`, `iconify::`, remote asset hosts | the hermetic-asset guard | pre-push |
| Helm, OpenTofu, Go, Hugo | the matching catalogue row | pre-push |
| Broken intra-doc links | `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps` | pre-push, offered not default |
| Long test suite | keep it in CI | not a hook |
| Other generated code | `settings.exclude`, or `--exclude` on one step | global or per step |

`pin-check` needs the `hashpinner` flake input, which the CI phase adds. Add the
step now behind a guard so it starts working when the input arrives:

```nix
let
  system = pkgs.stdenv.hostPlatform.system;
  hashpinner = inputs.hashpinner.packages.${system}.hashpinner-bin
    or inputs.hashpinner.packages.${system}.default;
in
{
  hk-nix.settings.hooks."pre-push".steps =
    lib.optionalAttrs (inputs ? hashpinner) {
      pin-check.check = "${lib.getExe hashpinner} --check";
    };
}
```

`hashpinner --check` is offline and shallow, which is why it may sit on
pre-push. `--deep` resolves the commit graph; it belongs in CI, never in
`checks.hk`.

For a committed `Cargo.nix`, also copy `templates/nix/hooks-cargo-nix.nix`. It
sets `settings.exclude` and adds the drift check that runs
`config.packages.cargo-nix --check`; that package comes from the crate2nix
module, so copy the file only in committed mode.

For secrets without a `.betterleaks.toml`, omit `--config`: betterleaks
auto-discovers only relative to the path it is given, and hk passes individual
files. Creating a config just to name it is worse than using the defaults.

## Activate

1. **Add the input** to `flake.nix`. Every nixpkgs-taking input follows nixpkgs;
   the intra-flake inputs follow their counterparts:

   ```nix
   hk-nix = {
     url = "github:nix-tools/hk-nix";
     inputs.nixpkgs.follows = "nixpkgs";
     inputs.flake-parts.follows = "flake-parts";
     inputs.treefmt-nix.follows = "treefmt-nix";
     inputs.import-tree.follows = "import-tree";
   };
   ```

2. **Import the module** in `nix/hooks.nix`:
   `imports = [ inputs.hk-nix.flakeModules.default ];`. With import-tree, no
   `flake.nix` import list changes.

3. **Wire the devshell** with two additive lines: `config.hk-nix.package` in
   `packages`, and `devshell.startup.hk.text = config.hk-nix.shellHook;` (or
   `shellHook = config.hk-nix.shellHook;` under `pkgs.mkShell`). Only add what is
   not already there. If the devshell's `just readme` recipe calls a bare
   `mdformat`, also add `config.treefmt.build.programs.mdformat`.

   The README step also needs `config.packages.cargo-readme`, pinned to 3.4.1 by
   `nix/cargo-readme.nix` and the `cargo-readme-src` input. When that file is
   absent, add both from `references/activation.md`; the devshell then lists
   `config.packages.cargo-readme` instead of `pkgs.cargo-readme`.

4. **Understand the two binaries.** `config.hk-nix.package` is the plain hk CLI.
   `config.hk-nix.hk` is the same binary with the generated config baked in as
   `HK_FILE`, and it is the one the installed hooks name by absolute store path.
   The startup hook prepends `config.hk-nix.hk` to `PATH`, so inside an activated
   devshell `hk` is the configured binary even though `packages` lists the plain
   CLI. Outside the devshell the hooks still work, because they name the store
   path directly. If the startup hook is skipped and the hook resolves a plain
   `hk`, `hk run --from-hook` treats the repository as not using hk, exits 0 and
   prints nothing; that is the usual "my hooks do nothing" report.

5. **There is no `hk.pkl`.** Current hk-nix bakes the rendered config into the
   binary. Do not add `hk.pkl` to the tree or to `.gitignore`, and treat older
   comments that say otherwise as stale.

Details and failure modes: `references/activation.md`.

## `checks.hk` and CI

Importing the module defines `checks.<system>.hk`, which copies the source into
the Nix sandbox, stages it in a throwaway git repo, and runs
`hk run <checkHook> --all --check` with `checkHook` defaulting to `pre-commit`.
Consequences:

- Every command in a hook that `checks.hk` runs must use an absolute store path.
  The sandbox has no devshell `PATH`. Builtins already inject their pinned tool.
- No network, no Cargo dependency closure, no `nix`, no private keys. A step that
  needs any of these must not be reachable from the check hook.
- The baseline `checks.hk` therefore proves formatting (and secret scanning if
  enabled) over all files, not deadnix or clippy. Deadnix and clippy belong in
  CI, or in a dedicated lint-only `check` hook that sets `checkHook = "check"`.

Do not put `hashpinner --deep`, `nix flake check`, `cargo test` or `sops` in the
check path. If a pre-commit step is sandbox-hostile, either give CI the missing
key or move the lint subset into a `check` hook and set `checkHook = "check"`;
never let `nix flake check` depend on a developer's local secrets.

## Verify

```bash
nix flake check
nix develop -c hk validate
nix develop -c hk run pre-commit --all --check
git config --local --get-regexp '^hook\.hk-'   # config-based hooks, git >= 2.54
git config --get core.hooksPath || echo "unset (config-based hooks)"
git commit --allow-empty -m "chore: test hooks"
git reset --soft HEAD^
```

- `nix flake check` builds the `checks.<system>.hk` derivation and is the only
  proof that the sandbox path works. Run it before claiming success.
- `hk validate` rejects a config hk could not load and warns about properties it
  would drop. Warnings count as failures here.
- The installed hook must name the store path of `config.hk-nix.hk`. With git
  2.54+ it is a `hook.hk-pre-commit.command` entry in `.git/config`; with the
  legacy layout it is a script in `.git/hooks/`. `core.hooksPath` is normally
  unset.
- The dry commit exercises pre-commit and commit-msg for real; the soft reset
  puts the branch back. Never commit real changes this way.
- A dry push runs pre-push: `git push --dry-run` only when a remote exists and
  the branch is one you would push. Never actually push from this skill.
- Measure the budget: `time git commit --allow-empty -m "chore: time hooks"`.
  If pre-commit is more than a second or two, move the step to pre-push; a slow
  hook is a design bug, not a discipline problem.

State what you syntax-checked (`nix-instantiate --parse`, `hk validate`) and
what the integration run must still prove (`nix flake check`, one real commit,
one real push). Do not claim the hooks run because the file looks right.

## Report

Finish with: files written or edited; which interview answers selected which
steps; what was skipped and why; the exact store-path references used; what was
parsed or validated; and what remains for the first real commit and push.

The next phase is the release: **Set up the tag-driven binary release.** The
tag-version guard here is the local half of that contract; the release workflow
is not part of this skill.
