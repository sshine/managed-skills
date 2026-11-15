---
name: rust-workspace
description: >-
  Set up a Cargo workspace and its dendritic Nix flake the house way: Rust crates
  under crates/*, workspace lints and dependencies, rust-toolchain.toml, a justfile,
  a README.tpl driven by cargo-readme, and crate2nix/rust-overlay/treefmt-nix/devshell
  flake-parts modules. Use when asked to set up a Cargo workspace, scaffold Rust
  crates, add workspace lints or dependencies, add a rust-toolchain, justfile or
  README.tpl, create a dendritic Nix flake, or wire crate2nix into a project.
  crate2nix is preferred and always wired; committing Cargo.nix is a question.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Scaffold a Rust workspace with a dendritic Nix flake

A Rust project here is a Cargo workspace even when it holds one crate: the workspace
owns the version, the lint table, the dependency versions and the Nix build. The flake
is dendritic: `flake.nix` is inputs plus `flake-parts.lib.mkFlake` plus
`import-tree ./nix`, and every `.nix` file below `nix/` is a module naming one concern.
Every file below has a starting point in this skill's `templates/`, mirroring its
destination path. Adapt it; do not invent a second layout.

## Read the repository first

| Found | Do |
|---|---|
| `Cargo.toml` with `[workspace]` | Merge missing `workspace.package`, lints, dependencies, members. Do not rewrite the file. |
| A single-package `Cargo.toml` | Convert it: move `[package]` into `crates/<name>/Cargo.toml`, keep the version, move shared deps into `[workspace.dependencies]`. |
| `rust-toolchain.toml` | Keep `channel` and `components`; add the musl targets if absent. |
| `flake.nix` or `nix/` | Add missing inputs and modules. Keep local choices and wording. |
| `justfile` | Add missing recipes; keep the project's existing comments and extras. |
| `.gitignore` / `.envrc` | Merge missing entries; keep the guarded `watch_file` loop rather than replacing it. |
| `README.tpl` / `README.md` | Keep the prose; ensure `{{crate}}`, `{{readme}}` and the License line survive. |
| `Cargo.nix` | Committed mode is already chosen. Do not switch to IFD without asking. |
| `nix/hooks.nix`, `nix/binary.nix`, workflows | Another phase owns them. Leave them untouched. |

## Ask once, then stop

Ask these in one batch, with the defaults, and wait. Each answer names the files it
changes.

| Question | Default | Changes |
|---|---|---|
| Member names and responsibilities | One binary crate named after the project | `crates/*`, `[workspace.dependencies]` |
| Which crates publish to a registry | None; a library the user names publishes | `rust-version`, `readme =`, internal path-dep versions |
| Native or system libraries (`gtk4`, `openssl`, …) | None | `nix/_cargo-nix.nix` overrides, devshell `PKG_CONFIG_PATH` / `LD_LIBRARY_PATH` |
| Commit `Cargo.nix` or generate it with IFD | Commit when the closure is large (~100 crates) or there are several binaries; IFD for a small single binary | `Cargo.nix`, `nix/cargo-nix.nix`, `nix/_cargo-nix.nix`, `nix/_package.nix`, `cargo-nix*` recipes, treefmt excludes |
| MSRV, if a library publishes | None for a binary-only workspace; otherwise the oldest stable that compiles | `[workspace.package].rust-version` |
| Root CLI README or a library README | Root `README.tpl` for the crate the repository is named after | `readme_args`, member `readme =` |

Do not ask about, or offer alternatives for: resolver 2, edition 2024, the two
workspace lints, `strip`/`lto`, treefmt, cargo-readme, the just verb names, the
dendritic layout, or MIT/Apache-2.0. These are the invariant.

Take `repository` from the existing manifest or `git remote get-url origin`. If
neither exists, ask for that one value before writing; an invented URL is worse than
a blank field.

## 1. The root manifest

Start from `templates/Cargo.toml`. The invariants:

| Table | Content |
|---|---|
| `[workspace]` | `resolver = "2"`, `members = ["crates/*"]` |
| `[workspace.package]` | `version`, `edition = "2024"`, `license = "MIT OR Apache-2.0"`, `repository`; `rust-version` only when a library publishes |
| `[workspace.lints.rust]` | `unused_must_use = "deny"` |
| `[workspace.lints.clippy]` | `unwrap_used = "deny"` |
| `[workspace.dependencies]` | one comment per concern, internal crates first, then CLI, errors, serialization, dev |
| `[profile.release]` | `strip = true`, `lto = "thin"` for a binary project |

Every member mirrors it:

```toml
[package]
name = "example"
version.workspace = true
edition.workspace = true
license.workspace = true
repository.workspace = true
description = "Say hello, once per greeting"
readme = "../../README.md"

[lints]
workspace = true

[dependencies]
clap.workspace = true
```

Write `clap.workspace = true` in members, never `clap = "4"`: a version repeated in a
member is a version that drifts. A member that needs a feature the workspace entry
does not enable belongs in `[workspace.dependencies]` as a new grouped entry, or gets
a local entry with a comment saying why.

Cargo requires a `version` beside a `path` dependency when the crate declaring it
is published, and then it must equal `[workspace.package].version` or
`cargo package` rejects it. Keep it on published internal crates; omit it on internal
crates that never publish, so `just bump` has one authoritative line. `just bump`
rewrites the copies that do exist.

## 2. rust-toolchain.toml

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
targets = ["x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl"]
```

The targets are what the release builds. rustup, rust-overlay and the devshell all
read this one file, so the compiler a developer gets is the compiler Nix builds with.

## 3. README.tpl and cargo-readme

The crate's `//!` docs are the CLI section; `README.tpl` is everything around it.
For a CLI the rubric is: `# {{crate}}`, a description, Installation (`nix run`, `nix
profile install`, `cargo install`, a prebuilt release link), a NixOS overlay section,
`## CLI` with `{{readme}}`, and a License line. Start from `templates/README.tpl`.

```bash
just readme        # write README.md
just readme-check  # fail if the committed file differs
```

`cargo readme` renders the template, splicing the crate's doc comments at
`{{readme}}`; `mdformat` then normalises the Markdown. `just readme` writes that
normalised output, `just readme-check` recomputes it and diffs, and treefmt runs the
same mdformat over `README.md`. The committed file is therefore a fixpoint of
`cargo readme | mdformat`; without mdformat the first pre-commit run rewrites
`README.md` and the next `readme-check` fails. Run `just readme` once after writing
the template and the docs; `just ci` checks it.

The devshell pins cargo-readme 3.4.1 from `nix/cargo-readme.nix`, so the generator
does not drift with nixpkgs. 3.4.1 resolves `--input` and `--template` against the
working directory, the repository root when the recipe or hook runs:

```bash
cargo readme --project-root crates/example --input crates/example/src/main.rs --template README.tpl
```

`--project-root` selects the member's manifest; `--input` and `--template` are
root-relative. A crate-relative path reads a different file without failing.

For a library, keep `# {{crate}}` and `{{readme}}`, replace the `nix run`/`cargo
install` block with the dependency snippet, and drop the CLI section. If several
crates publish, give each its own `README.tpl` and `readme = "README.md"`; the root
template stays with the crate the repository is named after. `references/readme.md`
covers the variables, path resolution and the failure modes.

## 4. The justfile

Start from `templates/justfile`. The base menu is fixed; add `watch`, `snap`, `bench`
or `demo` only when the project has a watch loop, snapshot tests, benchmarks or a
recording to keep.

| Recipe | Runs | Why |
|---|---|---|
| `default` | `just --list` | The menu is the documentation. |
| `fmt`, `fmt-check` | `treefmt`, then `--fail-on-change --no-cache` | One formatter for Rust, Nix and Markdown. |
| `lint` | `cargo clippy --all-targets --all-features -- -D warnings` | `--all-targets` is what lints tests. |
| `lint-nix` | `deadnix --fail nix/ flake.nix` | `Cargo.nix` is outside those paths. |
| `test`, `test-verbose` | `cargo test --all-features` | One test command; verbose adds `--nocapture`. |
| `build`, `doc` | `cargo build --release`, `cargo doc --no-deps` | Both pass `--all-features`; `doc` takes extra args. |
| `readme`, `readme-check` | Section 3 | |
| `lock-check` | `cargo metadata --locked` | Catches a manifest change without a lock update. |
| `cargo-nix`, `cargo-nix-check` | Committed mode only | Section 6. |
| `bump` | Section 4.1 | |
| `ci` | The chain above | What CI runs, in the same order. |
| `clean` | `cargo clean` | |

### 4.1 `just bump`

`just bump 0.2.0`, `just bump major`, `just bump minor` and `just bump patch` all
work. The recipe reads the current version from `[workspace.package]`, validates the
result as semver, rewrites that one line, rewrites `version` beside every internal
`path` dependency, runs `cargo update --workspace`, regenerates `Cargo.nix` only when
it is committed, and prints the next steps. It never creates or pushes a tag.

The printed sequence is the release order: review, `git add`, commit
`chore(release): vX.Y.Z`, push `main`, wait for the main CI run to go green, then run
the tag recipe. The tag recipe belongs to the release phase.

Why the wait is not politeness: the release workflow runs on a `v*` tag and reuses
the same Nix cache key as the main CI run. A tag pushed before main is green starts a
release job that compiles the same derivations from scratch while CI is still filling
the cache, so two jobs compete for one cache key and neither gets the other's work.
This is why bump and tag are separate recipes.

## 5. The dendritic flake

`flake.nix` is the inputs and the `mkFlake` call; everything else is a module.

| Module | Provides |
|---|---|
| `nix/systems.nix` | `x86_64-linux`, `aarch64-linux`, `aarch64-darwin` |
| `nix/rust-overlay.nix` | `_module.args.pkgs` with the rust-overlay |
| `nix/treefmt.nix` | nixfmt, the pinned rustfmt, mdformat |
| `nix/cargo-readme.nix` | `packages.cargo-readme`, pinned to 3.4.1 from `cargo-readme-src` |
| `nix/devshell.nix` | toolchain, treefmt wrapper, cargo-readme, deadnix, just, git, crate2nix |
| `nix/packages.nix` | `packages`, `apps`, `checks`, `flake.overlays.default` |
| `nix/_package.nix` | The build definition the overlay shares |
| `nix/_cargo-nix.nix` | The crate2nix instance and native overrides |
| `nix/cargo-nix.nix` | The regenerate/check helper (committed mode) |

The inputs are `nixpkgs` (channel tarball), `flake-parts`, `import-tree`,
`rust-overlay`, `treefmt-nix`, `devshell`, `crate2nix` and `cargo-readme-src` (a
non-flake source, `flake = false`). Every input that takes nixpkgs follows it;
`flake-parts`, `treefmt-nix` and `import-tree` are what hk-nix will follow later,
and `crate2nix` follows `flake-parts` and `devshell`.

Leave these seams:

- **Hooks phase.** Do not write `nix/hooks.nix`. The devshell carries
  `config ? hk-nix` guards around the hook package and the startup entry, so the
  module evaluates before that input exists and installs the hooks automatically
  after it lands. The hooks phase adds `hk-nix` to `flake.nix` and its own module.
- **Release phase.** The release phase adds `nix/release.nix` (the aarch64 musl cross
  linker, its `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER` environment and the
  `aarch64-musl-cc` package), the `dist`, checksum and tag recipes, `nix/binary.nix`
  and the release workflow. This phase does not create them.
- **CI phase.** This phase adds no workflows and no hashpinning input. The CI phase
  adds them, and every action it writes is pinned to a commit.

## 6. crate2nix

crate2nix is always wired. It emits one derivation per crate, so binaries, tests and
checks share the store paths for everything they have in common instead of compiling
the dependency tree once per output.

| | Committed `Cargo.nix` | IFD (`appliedCargoNix`) |
|---|---|---|
| Choose when | Closure is large (~100 crates) or several binaries ship | Small single binary |
| Evaluation | Fast; no store write | Builds the graph at evaluation and writes to the store |
| Overlay | Works: consumer builds with their own nixpkgs | Not practical; evaluation belongs to this flake |
| Drift | `just cargo-nix-check`, pre-push, CI | None to check |
| Files | `Cargo.nix`, `nix/cargo-nix.nix`, `nix/_cargo-nix.nix`, `nix/_package.nix` | `nix/packages.nix` calls `appliedCargoNix` |

**Committed mode.** Start from the templates. Generate the file, then prove the tree
agrees:

```bash
nix develop -c crate2nix generate
just cargo-nix-check
```

Keep `Cargo.nix` out of treefmt (`settings.global.excludes` in `nix/treefmt.nix`)
and out of deadnix (the `lint-nix` recipe scans only `nix/` and `flake.nix`). A hook
that passes staged files explicitly bypasses treefmt's exclusion, so the hooks phase
must repeat the exclusion on its command line; `references/crate2nix.md` has the
details.

**IFD mode.** Delete `Cargo.nix`, `nix/cargo-nix.nix`, `nix/_cargo-nix.nix` and
`nix/_package.nix`; replace `nix/packages.nix` with the `appliedCargoNix` form; drop
the `cargo-nix`/`cargo-nix-check` recipes from the justfile and `ci`; delete the
treefmt exclude; remove `inputs.crate2nix.packages` and `config.packages.cargo-nix`
from the devshell; and drop the overlay section of `README.tpl`, because an IFD
package cannot be built against a consumer's nixpkgs. `references/crate2nix.md` has
the replacement file verbatim.

Per-crate clippy through crate2nix is an optional refinement for large workspaces. Do
not enable it by default; a half-enabled flavour passes without looking at anything.

**Library-only workspace.** Keep the build under `checks`, drop `apps` and
`packages.default`, and expose no overlay; a library with a CLI packages its binary.

## 7. .gitignore and .envrc

`templates/.gitignore` covers `/target/`, `/.direnv/`, `/result`, `/dist/`, the two
crate2nix scratch files, and editor/OS noise. Do not add `hk.pkl`: the hook config is
baked into `HK_FILE`, not symlinked; add it only for the older symlinked config.

`templates/.envrc` is `use flake` plus a guarded `watch_file` loop over `flake.nix` and
`nix/*.nix`, so later phases' modules are watched without editing it again.

## 8. Verify

| Command | Proves |
|---|---|
| `just fmt-check` | Rust, Nix and Markdown are formatted. |
| `just lint` | Clippy passes with the workspace lints, tests included. |
| `just test` | The test suite passes under `--all-features`. |
| `just lock-check` | `Cargo.lock` matches the manifests. |
| `just cargo-nix-check` | Committed `Cargo.nix` matches the manifests (skip in IFD mode). |
| `nix flake check` | Every module evaluates and the checks build. |
| `nix build .#` | The package builds, both directly and through the overlay path. |
| `nix develop -c true` | The devshell evaluates, with or without the hooks input. |

Do not report the workspace as working because the files look right. Say which
commands you ran and which the integration run must prove. The templates were
syntax-checked with `nix-instantiate --parse`, a TOML parser and `just --list`, not
built; `nix flake check`, `just ci` and `nix build .#` are the proof.

## Hand off

When `just ci` passes and the tree is clean, the next phase is: **Wire the
repository's git hooks.** Stop there: this phase writes no hook module and no
workflow. After that: **Set up the tag-driven binary release.** The bump recipe
deliberately stops at the tag so that the release phase owns it.
