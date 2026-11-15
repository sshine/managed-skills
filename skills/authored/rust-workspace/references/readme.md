# README generation: `cargo readme` and `mdformat`

Three artifacts, three jobs:

| Artifact | Holds | Edited by |
|---|---|---|
| `crates/<name>/src/main.rs` (or `lib.rs`) | Crate-level `//!` docs: usage, modes, exit codes | Hand |
| `README.tpl` at the repository root | Motivation, installation, NixOS, License | Hand |
| `README.md` at the repository root | The rendered result | `just readme` only |

The split exists because the CLI help changes with the code and the installation
prose does not. Put the parts that must track the code in `//!` docs; put the parts
that must stay stable in the template.

## Template variables

`cargo readme` fills these when `--template` is given:

| Variable | Value |
|---|---|
| `{{crate}}` | Package name from `Cargo.toml` |
| `{{version}}` | Package version |
| `{{readme}}` | The crate's doc comments, with headings indented one level |
| `{{license}}` | The `license` field |
| `{{badges}}` | Badges rendered from the `[badges]` table |

A custom template disables the automatic title, license line and badge header, which
is why `README.tpl` writes `# {{crate}}` and the License line itself. Anything the
template does not mention does not appear.

Headings in the doc comments are shifted down one level, so `## Usage` in `main.rs`
becomes `### Usage` under the template's `## CLI`. Do not pre-shift them.

## Invocation and path resolution

The devshell installs `config.packages.cargo-readme`, which `nix/cargo-readme.nix`
pins to 3.4.1 from the `cargo-readme-src` input; the nixpkgs channel cannot move it.
3.4.1 resolves `--input` and `--template` against the current working directory,
which is the repository root when the recipe or the hook runs:

```bash
cargo readme --project-root crates/example --input crates/example/src/main.rs --template README.tpl
```

`--project-root` selects the member's manifest. `--input` and `--template` are
root-relative, so the redirect and the diff stay at the root without a subshell. A
crate-relative path reads a different file without failing.

In the member manifest, `readme = "../../README.md"` is what puts the generated file
into the published package.

## The mdformat fixpoint

```bash
just readme        # write README.md through cargo readme | mdformat
just readme-check  # recompute the same pipeline and diff it
```

`mdformat -` reads standard input and writes standard output. treefmt runs the same
mdformat over `README.md` in place, and the devshell installs that exact package as
`config.treefmt.build.programs.mdformat`, so the generated file is already the shape
the formatter wants. mdformat moves link reference definitions to the end of the
document, which is why `README.tpl` keeps `[releases]` there: the template and its
output agree on the first pass.

The committed `README.md` is therefore a fixpoint of `cargo readme | mdformat`. Two
consequences:

- If `just readme` omits mdformat (`cargo readme -o README.md`), treefmt rewrites the
  file on the first pre-commit run, and `just readme-check` then fails against the
  rewritten file. Always go through the pipe.
- If the devshell uses a different mdformat from the one treefmt wraps, the two
  disagree about the fixpoint. Install `config.treefmt.build.programs.mdformat`, not
  a second mdformat from nixpkgs.

Run `just readme` once after changing either the template or the `//!` docs, then
`just readme-check` before committing.

## Per-crate or root

The default is one root `README.tpl` for the crate the repository is named after, with
`readme = "../../README.md"` in that crate's manifest.

When several crates publish, each gets its own `README.tpl` and
`readme = "README.md"` next to its `Cargo.toml`. Give each one its own `readme_args`
line in the justfile and a `readme-<crate>` recipe, or a single recipe that loops over
the publishing crates; do not point two crates at one generated README, because the
`{{crate}}` and `{{readme}}` substitutions are per crate.

For a library, keep `# {{crate}}`, replace the Installation block with the dependency
snippet, and drop the CLI section:

````markdown
# {{crate}}

One sentence about the API.

## Installation

```toml
example = "0.1"
```

## Usage

{{readme}}

## License

MIT OR Apache-2.0.
````

## Failure modes

| Symptom | Cause |
|---|---|
| `Multiple workspace members found` | Pass `--project-root crates/<name>`; the workspace root is a virtual manifest. |
| `Could not open file 'src/main.rs'` | A crate-relative `--input`; 3.4.1 resolves it against the working directory. Spell it from the repository root. |
| `{{readme}}` is empty | The docs are `///` on an item, not `//!` at the crate root. |
| `readme-check` fails right after `treefmt` | mdformat is missing from the `readme` recipe, or a different mdformat is on `PATH`. |
| A doctest line shows up in the README | Hidden doctest lines must start with `# ` to be stripped. |
| A badge appears that the template did not ask for | The template contains `{{badges}}`; remove it to drop the badge header. |
