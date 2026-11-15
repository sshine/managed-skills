# Evaluations

## Triggering prompts

Each of these must load the skill.

1. "This Rust CLI builds fine, but I need people to run it without installing a Rust
   toolchain. Set up a tag-driven binary release: static musl tarballs for x86_64 and
   aarch64 Linux, a checksum beside each, and a release workflow on v* tags."

2. "Add a release workflow to this repository. On a v* tag it should build the macOS
   aarch64 binary on a native runner, draft a GitHub release, publish to crates.io only
   after both builds pass, and make the release public last."

3. "I tagged v0.3.0 but the release workflow started before main's CI was green and the
   Nix cache was cold. Explain what went wrong, then give me a `just tag` recipe that
   refuses to do that again. Also, what prints the SRI hashes for nix/binary.nix?"

## Behavioural prompt

Repository state, stated to the agent as fact:

> `/tmp/eval/example` is a single-binary Rust workspace on GitHub: `crates/example` with
> `[workspace.package] version = "0.1.0"`, a `justfile` whose `ci` recipe is
> `fmt-check lint test build`, a pinned `rust-toolchain.toml`, and
> `.github/workflows/rust.yml` with every action pinned. There is no
> `.github/actions/setup-nix`, no `nix/binary.nix`, no `nix/release.nix`, and
> `.github/workflows/release.yml` currently only runs `echo todo`. The crate name
> `example` is taken on crates.io, so do not publish there. Everything else: macOS
> aarch64 yes, draft release, pin nix/binary.nix, keep the existing asset names if any.
> Set up the release.

Pass criteria:

- `check-version` compares against `cargo pkgid -p example` and prints both the tag and
  the crate version on mismatch. Running it with `v0.2.0` fails; `v0.1.0` passes.
- `dist-linux` clears `dist/`, builds both musl targets with `--locked --target`, writes
  `example-v0.1.0-x86_64-unknown-linux-musl.tar.gz` and the aarch64 equivalent, each with
  a `.sha256` sidecar, and keeps the tag's `v` in the name.
- `just tag` refuses on a dirty tree, a non-`main` branch, a HEAD not equal to
  `origin/main`, an existing local or remote tag, and a version mismatch; it reads
  `gh run list --branch main --workflow ci.yml --limit 1 --json conclusion` when `gh`
  is available and otherwise prints a URL and requires `CONFIRM=green`.
- `release.yml` triggers on `v*`, has `contents: write`, creates the draft before the
  build jobs, has a Linux and a macOS leg, smoke-tests the extracted tarball, uploads with
  `gh release upload --clobber`, undrafts last, and contains no crates.io step.
- Every `uses:` is a 40-character commit SHA with a `# vX.Y.Z, YYYY-MM-DD` comment; no
  `@v4`-style moving reference is introduced.
- Because `.github/actions/setup-nix` is absent, the workflow inlines the pinned install
  and cache steps instead of inventing a composite, and leaves `rust.yml` untouched.
- `nix/binary.nix` uses `fetchurl`, `optionalAttrs` keyed by Nix system, a `version` that
  trails `Cargo.toml` with the "bump after the workflow finishes" comment, and hashes that
  are clearly to be filled from `just release-hashes` rather than invented.
- The reply states that no tagged run happened, so the workflow, the cross linker and the
  hashes are unverified.
- Fails if it publishes to crates.io, claims the release was tested, or renames the
  tarballs to drop the `v`.

## First-release gate

The behavioural prompt must end with a tag, a finished Release workflow, verified assets
and checksums, and `nix/binary.nix` pinned to the published hashes and building. A
release workflow that has never run is not a pass. If the user said "scaffold only", say
so explicitly and skip this gate.

## Negative prompt

Must not load the skill:

> "Bump the workspace version from 0.1.0 to 0.2.0, update `Cargo.lock`, and fix the two
> clippy warnings in `crates/example/src/lib.rs`."

That is a version bump and a lint fix: no tag, no artifacts, no forge release.
