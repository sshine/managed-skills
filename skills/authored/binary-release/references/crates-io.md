# crates.io

Publishing is the only irreversible step in a release. A version that is uploaded can be
yanked — hidden from new resolutions — but never deleted, and the version number is spent
forever. Everything below is about keeping that step last and boring.

## 1. Is the name free?

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://crates.io/api/v1/crates/example
cargo search example --limit 1
```

| response | meaning |
|---|---|
| `404` | free; nothing published under that name |
| `200` | taken; the name belongs to whoever holds it, yanked or not |

Do not ask the user whether the name is free; check and report. Names are first-come and
stay with their owner, so a taken name means choosing a different crate name — not a
different owner for the same one.

Ask: *should the release publish to crates.io, and which secret holds the token?* If the
answer is no, the step is deleted rather than commented out, so a reader does not wonder
whether it runs.

## 2. What is publishable

- A library with a public API is the reason to publish.
- A binary is often not. Many CLIs here ship tarballs only; that is a valid answer.
- Internal crates get `publish = false` in their `[package]` table. `cargo publish
  --workspace` then skips them instead of failing.

Every internal path dependency that a published crate references must carry a `version`
as well as a `path`:

```toml
[dependencies]
example-core = { version = "0.1.0", path = "../example-core" }
```

Without it, `cargo package` builds a manifest the registry cannot resolve. With it, a
stale version string resolves against the last published release instead of the sources
beside it — silently. That is why `check-version` asserts the workspace dependency string
too when one exists, which one of the workspaces here does in its release recipe:

```bash
dep="v$(grep -oP '(?<=^example-core = \{ version = ")[^"]+' Cargo.toml)"
[ "$dep" = "{{version}}" ] || { echo "dependency version $dep, tag {{version}}" >&2; exit 1; }
```

## 3. Package before publish

```bash
cargo package --locked -p example           # build the .crate, no upload
cargo package --locked -p example --list    # what went into it
```

`cargo package` is the rehearsal: it applies `include`/`exclude`, rewrites path
dependencies to registry versions, and builds from the packaged source. A missing file or
a bad manifest fails here, while it is still reversible. Put it before the publish step in
the workflow and in `just ci` (`package-check`), not after.

`--locked` means the lock file must already satisfy the manifests; it is what stops a
publish from resolving a fresh dependency the release never tested.

## 4. Publish in dependency order

Libraries first, then the binaries that depend on them:

```bash
cargo publish --locked -p example-core
cargo publish --locked -p example
```

The registry has to carry `example-core`'s version before it can resolve `example`'s
dependency on it. `cargo publish` waits for the index to make each upload visible before
it returns, so consecutive steps need nothing between them in practice; if a resolution
error appears anyway, wait a minute and retry the dependent crate.

One tag releases everything, because every member inherits one workspace version. There
is no per-crate tag.

## 5. The token

```yaml
- name: Publish to crates.io
  env:
    CARGO_REGISTRY_TOKEN: ${{ secrets.CRATES_IO_TOKEN }}
  run: nix develop -c cargo publish --locked -p example
```

- `CARGO_REGISTRY_TOKEN` is what cargo reads; the secret's name is a repository choice.
  Use the name the user gives, and the same name in every workflow.
- The token is a crates.io API token scoped to publish. It is not reusable across
  registries, and it must not be logged.
- For a Forgejo runner, the secret lives in that forge's repository settings. The shell
  uploader uses `FORGEJO_TOKEN`; the two are different secrets.

## 6. What cannot be undone

| action | reversible? |
|---|---|
| `cargo package` | yes, a local file |
| `cargo publish --dry-run` | yes, uploads nothing (still runs the package build) |
| `cargo publish` | no: the version is public and permanent |
| `cargo yank --version` | partially: hidden from new resolutions, still downloadable, number still spent |
| deleting a GitHub/Forgejo release | yes, but the tag and any pinned hash remain |

A wrong publish is fixed by publishing a new patch version, not by editing the old one.
That is why the order in `.github/workflows/release.yml` is: both build legs, sidecar
check, crates.io, and only then `gh release edit --draft=false`. A failure before the
undraft leaves an invisible draft; a failure during the publish leaves the earlier crates
published, which is why libraries go first and the binary that depends on them last.

## 7. After the first publish

- The crate page's repository, license and README come from the manifest and the
  generated `README.md`; check them on the first release, not the fifth.
- `nix/binary.nix` and crates.io are independent: the tarball is the fast install, the
  crate is the portable one. Neither replaces the other.
- A publish step that is retried after a success fails with "crate version already
  uploaded"; that is expected, and the remaining jobs can still undraft. Guard it only if
  the workflow retries often:

  ```bash
  set -o pipefail
  cargo publish --locked -p example 2>&1 | tee /tmp/publish.log \
    || grep -q 'already uploaded' /tmp/publish.log
  ```

  Prefer fixing the workflow ordering over adding this.
