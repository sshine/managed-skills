---
name: bump-and-release-e2e
description: >-
  Cut, verify, publish, and deploy a tag-driven binary release end to end. Use
  whenever the user asks to bump a version, cut or tag a release, publish a
  binary release, cut the first release of a new project, use a release
  workflow that was just scaffolded, update a downstream NixOS flake, or
  redeploy this machine.
  Enforces local CI and green main CI before tagging, polls the Release
  workflow, pins release hashes, and updates and switches the downstream flake.
  Never tags a commit before main CI has passed.
metadata:
  version: "1.0"
---

# Bump and release end to end

A release is not finished when the tag is pushed. It is finished when the
tagged commit is green, the assets exist, the binary pin points at them, and
the machine runs the new version.

The rule this skill exists for: **do not tag before main CI is green.** A tag
starts a second workflow that competes for the same Nix cache key as main CI,
and a bad tag is public immediately. Bump, push main, wait, then tag.

A scaffolded release workflow is not a release. If the project's release machinery was
just set up and the user did not say "scaffold only", this skill is the next step: use it
to bump or tag, publish, and pin the hashes.

## Expected repository shape

Adapt names when a repository differs, but keep the order.

- Tag `vX.Y.Z` matches `[workspace.package].version`.
- `.github/workflows/ci.yml` runs on `main`.
- `.github/workflows/release.yml` runs on `v*`.
- `just ci`, `just dist <tag>` (or `dist-linux`/`dist-macos` as the repository
  provides), and `just release-hashes <tag>` exist.
- `nix/binary.nix` pins the published tarballs, when there is one.
- The machine deploys from `~/Projects/nixos` with `just switch`.

`scripts/release-e2e.sh` implements the repetitive parts. Run it through the
devshell, because it uses `just`, `gh`, `jq`, `nix`, and `cargo`:

```console
$ nix develop -c scripts/release-e2e.sh --help
```

Environment overrides: `REPO`, `BRANCH`, `CI_WORKFLOW`, `RELEASE_WORKFLOW`,
`DOWNSTREAM`, `INPUT`, `BINARY`, `POLL_SECONDS`, `WAIT_SECONDS`.

## The sequence

### 1. Preflight

```console
$ git status --short          # clean, or only the release change
$ git branch --show-current   # main
$ git fetch origin main
$ gh auth status
$ just --list | grep -E 'ci|dist|release-hashes'
```

Stop if the tree is dirty, the branch is not the release branch, or `gh` is not
authenticated. Never bury a release among unrelated changes.

### 2. Bump, commit, and run local CI

For a first release with no prior tag, publish the current version (for example
`0.1.0`); do not invent a `0.2.0`. Otherwise always bump minor: `0.3.0` becomes
`0.4.0`, and `1.4.2` becomes `1.5.0`. Use the repository's bump recipe when it has
one; otherwise update `[workspace.package].version`, the `version` beside every
`path = "crates/*"` workspace dependency, and `Cargo.lock`.

```console
$ nix develop -c scripts/release-e2e.sh bump
$ git show --stat HEAD
$ git push origin main
```

`bump` refuses a dirty tree, computes the next minor version, updates the
version, runs local CI, and commits `chore(release): vX.Y.Z`. Do not push a
local commit that skipped local CI.

### 3. Wait for green main CI

```console
$ nix develop -c scripts/release-e2e.sh wait-ci
```

The script polls the `ci.yml` run whose `headSha` is local `HEAD`. It refuses to
return while that exact commit is queued or running, and prints the failing run
and its logs if it fails. Do not tag a commit whose run is missing, cancelled,
or red.

### 4. Tag and wait for the Release workflow

```console
$ nix develop -c scripts/release-e2e.sh tag vX.Y.Z
$ nix develop -c scripts/release-e2e.sh wait-release vX.Y.Z
$ gh release view vX.Y.Z
```

`tag` re-checks that the tree is clean, `HEAD` equals `origin/main`, the manifest
version matches, the tag does not exist locally or remotely, and CI for `HEAD`
is green. It then creates an annotated tag and pushes only that tag.

If the repository already has a `just tag` recipe that enforces the same gate,
use it instead. Do not use a tag recipe that only checks the working tree.

### 5. Pin the release hashes

Only after the Release workflow has published the assets:

```console
$ nix develop -c scripts/release-e2e.sh hashes vX.Y.Z
```

Paste the values into `nix/binary.nix`, bump its `version` to `X.Y.Z`, then:

```console
$ nix build .#<name>-bin
$ git add nix/binary.nix
$ git commit -m "chore(nix): pin vX.Y.Z release hashes"
$ git push origin main
$ nix develop -c scripts/release-e2e.sh wait-ci
```

`nix/binary.nix` deliberately trails `Cargo.toml`; it names the last published
release. Never take hashes from a local `dist/`: local builds are not
bit-identical to the release assets, and `fetchurl` will reject them. Use
`release-hashes`, which hashes the published tarballs.

Do not skip the second green-main wait. The downstream flake should point at a
commit whose main CI actually passed.

### 6. Update and switch the downstream flake

Skip this step when the project has no downstream flake input; say so explicitly.

```console
$ nix develop -c scripts/release-e2e.sh downstream --tag vX.Y.Z
```

This enters `~/Projects/nixos`, runs `nix flake update <input>`, stages only
`flake.lock`, runs `just switch`, and verifies the installed binary reports the
new version.

- Leave any unrelated staged changes in the downstream repository alone.
- Stage only `flake.lock`; do not `git add -A` there.
- If the switch fails, stop and report. The release is already published; do
  not retry destructive system changes blindly.
- If the downstream uses a different input name or binary name, pass `--input`
  and `--binary`.

### 7. Report

Finish with:

- tag and Release URL;
- main CI and Release workflow results;
- whether `nix/binary.nix` was pinned;
- downstream input revision and staged path;
- `just switch` result and installed `--version`;
- anything the next release must still prove, such as a new target.

## Failure policy

Work through these in order.

1. **Retry once when the failure looks sporadic.** Runner resource, network,
   cache, permission, or a cancelled job: rerun the failed workflow once with
   `gh run rerun <id> --failed` and poll again. Do not retry a compiler error,
   a test failure, or a bad tag.
2. **Fix once, then retry.** If it is a real failure, make one focused fix on
   `main`, commit, push, and wait for green. A tag must never point at a red
   commit.
3. **Fall back to a local release only when the tag's commit is good but the
   Release workflow cannot publish.** Check out the tag, verify the tree is
   clean, build with `just dist vX.Y.Z`, and publish with `gh release`:

   ```console
   $ git switch --detach vX.Y.Z
   $ nix develop -c scripts/release-e2e.sh local-release vX.Y.Z
   ```

   `local-release` refuses a dirty tree, uses the repository's `dist` or
   `dist-linux` recipe, uploads if the release exists, and creates it otherwise.
   It does not invent a tag and does not move a published tag. If the failure
   was a real build error, fix it and cut the next patch release instead.

Never force-push or move a published tag. Never delete release assets to hide a
failed run. Never tag a red commit because the release "should" work.

## Boundaries

- This skill assumes GitHub Actions and the `gh` CLI. For Forgejo, adapt the
  polling and publishing commands; keep the order and the green-main gate.
- Version bumps belong here. Release workflow setup, hook wiring, and binary
  target matrices belong to their own setup skills. This skill is the act; a
  scaffolded workflow is not a release.
- The downstream switch is for this machine's NixOS configuration. Do not
  deploy to remote hosts unless the user explicitly asks.
