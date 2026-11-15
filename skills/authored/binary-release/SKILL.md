---
name: binary-release
description: >-
  Set up the tag-driven binary release for a Rust CLI or workspace: static musl tarballs
  for x86_64-linux and aarch64-linux, checksums, optional macOS aarch64, and a GitHub or
  Forgejo release workflow. Use when asked to release binaries,
  publish a GitHub/Forgejo release, add a release workflow, produce static musl artifacts
  with checksums, enable crates.io publishing, pin nix/binary.nix to published tarballs,
  tag a version, or wire the tag-driven binary release phase of a new project. Also
  covers draft releases, smoke-testing the artifact that ships, and why a tag pushed
  before main is green competes for the Nix cache key instead of restoring it.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Tag-driven binary releases

A release here is one tag, `vX.Y.Z`, equal to `[workspace.package].version`, plus a set of
tarballs attached to that tag and, later, pinned by `nix/binary.nix`. The tag is the
contract: everything downstream (the release workflow, the checksum sidecars, the pinned
hashes, the crates.io publish) is derived from it and none of it is typed by hand twice.

This is the release phase of a project: set up the tag-driven binary release once the
workspace and its CI exist, and not before.

| artifact | runner | asset name |
|---|---|---|
| static musl x86_64 | ubuntu-latest, Nix devshell | `example-v0.1.0-x86_64-unknown-linux-musl.tar.gz` |
| static musl aarch64 | same job, cross linker | `example-v0.1.0-aarch64-unknown-linux-musl.tar.gz` |
| macOS aarch64, if asked | native `macos-15` | `example-v0.1.0-aarch64-apple-darwin.tar.gz` |
| checksum per tarball | same job as the tarball | `<asset>.sha256` |

The version in the asset name is the tag verbatim, `v` included, because
`nix/binary.nix` builds the download URL from the tag. Do not strip the `v` from one
side only; that mismatch is a 404 at evaluation time.

## Check the repository before writing

```bash
just --list | grep -E 'check-version|dist|tag'
ls nix/binary.nix nix/release.nix .github/workflows/release.yml .forgejo/workflows/release.yml
ls .github/actions/setup-nix/action.yml
git tag --sort=-v:refname | head
```

- A recipe that already exists is kept, not re-added; `just` fails on a duplicate name.
- A workflow that already exists is edited additively. Keep its asset names: an existing
  `nix/binary.nix` and any downstream consumer depend on them.
- `nix/binary.nix` is added only if asked; `nix/release.nix` only if aarch64-linux is
  cross-built from x86_64.
- Follow the repository's existing form: which GitHub actions it pins and how it spells
  the cache key. Do not rewrite `.github/actions/*`; call them.

## Ask, in one batch

Ask only this, and say which files each answer changes:

1. Is the crate name free on crates.io (check it, don't ask the user to), and should the
   release publish there? Which secret holds the token? Changes the `cargo publish` step
   and `references/crates-io.md`.
2. macOS aarch64: yes or no; also x86_64-apple-darwin? Changes the `macos` job and one
   `hashes` entry.
3. Draft release first, or public immediately? Default: draft. Changes the `draft` job.
4. Pin `nix/binary.nix` to the published tarballs? Default: yes for a CLI. Changes
   `nix/binary.nix`.
5. Any extra targets (windows, linux-gnu, x86_64-apple-darwin)? Changes the matrix and
   the `case` in `release-hashes`.
6. GitHub, Forgejo, or both? Changes which workflow is written.

Never ask about: the tag format, the `.sha256` sidecars, static musl as the Linux
default, tarball naming, the version bump recipe, or the action pinning policy. Those are
fixed here.

## 1. The tag is the version

`check-version` compares the tag against what cargo would publish, and is the first thing
the workflow runs:

```bash
just check-version v0.1.0
cargo pkgid -p example          # what it compares against
```

It reads one member because every member inherits `[workspace.package].version`. If the
workspace also names a sibling crate's version in `[workspace.dependencies]`, that string
cannot inherit and needs its own assertion (the pattern is in `references/crates-io.md`).

The pre-push `tag-version` hook, wired in the hooks phase, is the second line of defence:
it reads the version out of the tagged commit with `git show` and refuses a `v*` tag whose
commit disagrees. `check-version` catches the mistake before the build starts;
`tag-version` catches a tag made outside `just tag`. Both exist because either one alone
can be bypassed.

## 2. Append the recipes

Copy `templates/justfile-release.just` onto the end of the existing `justfile`, replace
`example` with the crate, and delete the optional AppImage block unless the project is a
GUI application.

| recipe | purpose |
|---|---|
| `check-version version` | tag equals the manifest version; clear error on mismatch |
| `dist-linux version` | clean `dist/`, both musl targets, tarball plus `.sha256` each |
| `dist-target version target` | one target, appends; for a matrix leg |
| `dist-macos version` | aarch64-apple-darwin on a Mac, `shasum` sidecar |
| `release-hashes version` | the SRI lines for `nix/binary.nix`, read from the release |
| `dist-hashes` | the same lines from local `dist/`, only for downloaded assets |
| `tag version` | the refusals, the green-main gate, then tag and push |

`tag` refuses unless the tree is clean, HEAD is exactly `origin/main`, the tag exists
neither locally nor on origin, and the manifest matches. Then it checks the CI workflow's
latest run on main:

- with `gh` authenticated: `gh run list --branch main --workflow ci.yml --limit 1
  --json conclusion` must say `success`, and the failing run list is printed otherwise;
- without `gh`: print the URL and require `CONFIRM=green just tag v0.1.0`.

The workflow filter matters: a green docs or release run on main is not the CI run whose
cache the release is trying to reuse. Set the `ci_workflow` variable to the repository's
actual CI workflow file.

Tagging before main is green starts two jobs that need the same Nix cache key, so both
compile and neither saves. `references/release-sequence.md` has the commands and the
recovery for a tag already pushed.

## 3. `nix/release.nix` only when aarch64-linux is cross-built

Add `templates/nix/release.nix` when the aarch64 musl binary is built on an x86_64
runner: it puts `pkgsCross.aarch64-multiplatform-musl.stdenv.cc` in the devshell and sets
`CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER`. rustc links x86_64 musl unaided; only a
foreign architecture needs a linker. The body is guarded to `x86_64-linux`: import-tree
imports every module on every configured system, and an unguarded cross compiler would
land in an aarch64-darwin devshell.

If aarch64 is built on a native arm runner (`ubuntu-24.04-arm`), say so in the workflow
comment and do not add the file. If a dependency compiles C (`ring` through `rustls`),
a linker is not enough: both musl targets also need `CC_x86_64_unknown_linux_musl` and
`CC_aarch64_unknown_linux_musl`, underscored because devshell exports them.

## 4. `nix/binary.nix`

`templates/nix/binary.nix` is the consumer side of the release: `fetchurl` of each
published tarball, `runCommand` to unpack it, `makeWrapper` when the binary shells out.

- The pinned `version` deliberately trails `Cargo.toml`; it names the last released tag.
  Bump it after the workflow finishes, never as part of the bump commit.
- The hash map is keyed by Nix system, and `lib.optionalAttrs (hashes ? ${system})` gives
  unsupported systems no package at all, so `nix flake check` stays green on Darwin.
- `lib.fakeHash` in the template is intentional: the first build fails with the real hash
  in the message. Replace it with `just release-hashes v0.1.0` output once assets exist.
- The package is `<name>-bin`, not `default`, so the source build stays the default.

## 5. The GitHub release workflow

`templates/.github/workflows/release.yml`, triggered by `v*` tags with
`permissions: contents: write`.

| job | what it proves |
|---|---|
| `gate` | tag matches the manifest; `just ci` passes on the tagged commit |
| `draft` | `gh release create --draft` up front, so assets land somewhere invisible |
| `linux` | both musl tarballs, x86_64 smoke-tested from the tarball, assets uploaded |
| `macos` | aarch64 tarball on `macos-15`, smoke-tested, assets uploaded |
| `publish` | sidecar check, package check, crates.io if enabled, undraft |

- Draft rather than a public release or `upload-artifact`: a draft has the tag's asset
  namespace, so `gh release upload --clobber` is idempotent and a retried leg replaces
  its own assets. `upload-artifact` would need a download-and-reupload job to produce the
  same names, and a public release would show a half-populated page when a leg fails.
- Smoke-test the tarball that ships, not `cargo run` or a host-native build. The aarch64
  Linux tarball cannot execute on the x86_64 runner: extract it and verify its sidecar,
  and say that is all CI proves.
- Checksums are per-job sidecars computed over the tarball that job built, uploaded
  beside it. Do not hash the assets after download instead; one method, not two.
- Pin every `uses:` to a commit with a `# vX.Y.Z, YYYY-MM-DD` comment. Copy SHAs from the
  repository or the ones in this skill; never invent one. `just pin-check` or
  `hashpinner --check --deep` verifies them.
- macOS uses the runner's rustup and no Nix, so it cannot share the Linux cache key and
  does not need to. `rust-toolchain.toml` pins the version either way.
- crates.io steps are the only ones that cannot be undone. Delete them unless publishing
  was requested; see `references/crates-io.md`.

## 6. The Forgejo release

Forgejo gets `.forgejo/workflows/release.yml` with `runs-on: nixos` and absolute action
URLs (`uses: https://github.com/actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803`).
There is no cache step: the runner's store is the cache. The upload is
`nix run .#forgejo-release -- v0.1.0 dist`, backed by
`templates/nix/forgejo-release.nix`:

```bash
FORGEJO_URL=https://git.example.com \
FORGEJO_REPO=owner/example \
FORGEJO_TOKEN=... \
nix run .#forgejo-release -- v0.1.0 dist
```

The script adopts an existing release for the tag, deletes an asset of the same name, then
uploads, so a rerun completes a partial release instead of duplicating assets. Forgejo
posts a duplicate rather than replacing it, which is why the delete is there. The release
is public as soon as it is created; if that is unacceptable, add `draft: true` and PATCH
it public after the last asset.

The template builds Linux only. A Forgejo instance usually has no macOS runner; if macOS
was requested, ask whether the instance has an `macos` label and add a second job using
`dist-macos`, or state plainly that macOS is GitHub-only for this project. Do not let the
absence of a macOS job look like an oversight.

## 7. macOS

Native `macos-15` is arm64: no cross SDK, no `osxcross`, no linker variables. The tarball
is a normal dynamic executable that links libSystem, not a static binary, so do not
promise "static" for it. The runner's rustup reads `rust-toolchain.toml`, and
`aarch64-apple-darwin` belongs in that file's `targets` list. `shasum -a 256`, not
`sha256sum`. `references/macos.md` covers the matrix, the smoke test and the reasons not
to cross-compile.

The workflow uses the runner's `just` when present and `brew install just` when it is
not. That is the only non-Nix tool in the release. If the project already installs Nix on
macOS, use `nix develop -c just dist-macos` instead so the toolchain has one source.

## 8. crates.io

Before writing the step:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://crates.io/api/v1/crates/example
cargo search example --limit 1
```

`404` means the name is free; `200` means it is taken, and the crates.io policy is that a
name belongs to whoever holds it. Then ask whether publishing should be enabled, and
which secret holds the token (`CARGO_REGISTRY_TOKEN` in the step, `secrets.CRATES_IO_TOKEN`
by default). Publishing is permanent: a version can be yanked, never deleted or reused.
Publish libraries before the binaries that depend on them, since the registry has to
carry each version before the next crate resolves it, and check that every internal path
dependency carries a `version` next to its `path`. `references/crates-io.md` has the
publish order, the `--locked` and `package` pre-flight, and the rest.

## 9. The sequence

The bump is the workspace phase's `just bump`; this phase starts from a committed version.

```bash
just bump 0.1.0          # workspace phase: one line in [workspace.package]
just fmt && just ci      # review the diff
git commit -am "chore: release 0.1.0"
git push origin main
gh run watch             # or: gh run list --branch main --limit 1
just tag v0.1.0          # refuses until the run above is green
```

Pushing the tag is what starts the release workflow, and that workflow restores the cache
key main's CI just wrote. Reversing the last two lines makes both jobs compile the same
derivations without either saving them.

After the workflow finishes:

```bash
just release-hashes v0.1.0   # paste into nix/binary.nix, bump `version`, commit
nix build .#example-bin
./result/bin/example --version
```

## Verify

```bash
just --list | grep -E 'check-version|dist-linux|tag'
just check-version v0.1.0
just --dry-run dist-linux v0.1.0
nix flake check -L
```

What only a real tagged run proves: that the cross linker resolves inside the devshell,
that both runners produce the named assets, that `gh release upload` accepts them, and
that `nix/binary.nix`'s hashes match the bytes. Say that plainly instead of claiming the
release works.

## Not this phase

- The version bump, `[workspace.package]`, and `rust-toolchain.toml` targets belong to
  the workspace phase.
- `tag-version` and the other hook steps belong to the hooks phase.
- The CI workflow, `.github/actions/*`, and the hashpinner input belong to CI setup. Call
  the composites if they exist; never rewrite them.
- A GUI project's AppImage build is optional here and has its own module; the recipe in
  the template only packages what that module produces.

## Files

- `templates/justfile-release.just` — recipes to append, not a whole justfile.
- `templates/nix/release.nix`, `templates/nix/binary.nix`,
  `templates/nix/forgejo-release.nix`.
- `templates/.github/workflows/release.yml`,
  `templates/.forgejo/workflows/release.yml`.
- `references/crates-io.md`, `references/macos.md`, `references/release-sequence.md`.
