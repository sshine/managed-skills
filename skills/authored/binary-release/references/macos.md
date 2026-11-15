# macOS aarch64

macOS is a selected target, not a default. When it is selected, build it on a native
`macos-15` runner. `macos-15` is Apple Silicon, so the host architecture is the target
architecture and nothing has to be crossed.

## Why not cross-compile from Linux

- `aarch64-apple-darwin` needs the macOS SDK for its linker and system libraries. Apple's
  license does not let it be redistributed, so it cannot be a Nix input the way musl's crt
  objects are. `osxcross` exists, and pulling a copy of the SDK into a Linux build is the
  problem it does not solve.
- The flake lists `aarch64-darwin` so a Mac can evaluate its own system. That is not a
  promise that a Linux host can build it; nixpkgs' Darwin stdenv needs the Apple
  toolchain on a Darwin host.
- The native runner is available, arm64, and takes about a minute for a small CLI. The
  cross toolchain would be more code and more failure modes for a slower, less certain
  result.

The same runner also carries the x86_64 SDK, so an Intel build is one extra matrix entry
in the same job image:

```bash
rustup target add x86_64-apple-darwin
cargo build --release --locked --target x86_64-apple-darwin -p example
```

Only add it when asked: an arm64 binary will not run on an Intel Mac, but most projects
here ship arm64 only.

## Toolchain: rustup, not Nix

The macOS job uses the runner's preinstalled rustup, which reads `rust-toolchain.toml`
from the checkout, so the compiler version is the same as in the Linux devshell. Adding
`aarch64-apple-darwin` to that file's `targets` list is the one edit the workspace phase's
file needs; then `rustup target add` in `dist-macos` is a no-op rather than a requirement.

Nix on macOS is not wrong, only unnecessary here: it would install a second toolchain,
add a `aarch64-darwin` cache key that shares nothing with the Linux one, and buy nothing
for a build that has no C dependencies. If the project already uses a Nix devshell on
macOS for other reasons, install it the same way as on Linux and run
`nix develop -c just dist-macos`; keep the cache key separate, since `runner.os` is
already part of it.

## The job

```yaml
  macos:
    needs: draft
    runs-on: macos-15
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0, 2026-07-16
      - run: |
          set -euo pipefail
          command -v just >/dev/null || brew install just
          just dist-macos "${GITHUB_REF_NAME}"
```

`just` is not guaranteed on the image; `brew install just` costs seconds when it is
missing and nothing when it is present. `cargo`, `rustup`, `gh`, `tar` and `shasum` are
present already, which is why nothing else is installed.

## Archive naming

```
example-v0.1.0-aarch64-apple-darwin.tar.gz
example-v0.1.0-aarch64-apple-darwin.tar.gz.sha256
```

The tarball contains the bare binary at its root, matching the Linux tarballs, so
`tar -xzf` plus `install -Dm755` is the same two lines in every `nix/binary.nix` branch.
The version is the tag verbatim, `v` included.

macOS ships `shasum`, not `sha256sum`; `shasum -a 256 example-v0.1.0-aarch64-apple-darwin.tar.gz
> example-v0.1.0-aarch64-apple-darwin.tar.gz.sha256` produces the same text format, and
Linux `sha256sum -c` reads it.

## Smoke test

Run the binary that ships, from the tarball:

```bash
tar -xzf "dist/example-v0.1.0-aarch64-apple-darwin.tar.gz" -C /tmp
/tmp/example --version
( cd dist && shasum -a 256 -c example-v0.1.0-aarch64-apple-darwin.tar.gz.sha256 )
```

Because the runner is arm64, this actually executes the artifact, unlike the aarch64
Linux tarball on an x86_64 runner. It is the strongest smoke test in the matrix; rely on
it for `--version` and a cheap subcommand, not for a test suite.

A macOS binary is not static: `otool -L /tmp/example` shows libSystem and any system
frameworks the crate links. Do not describe it as static in the README.

## What users will hit

- The archive is not signed or notarized. A browser download gets the quarantine
  attribute, and an unsigned binary then needs `xattr -d com.apple.quarantine ./example`
  or the equivalent in System Settings. A tarball fetched with `curl` or by Nix does not
  get the attribute. Worth one line in the release notes.
- An arm64 binary does not run on an Intel Mac, and Rosetta translates the other
  direction only. If Intel users matter, add the second matrix entry above.
- The minimum macOS version is whatever the SDK targets by default. Do not promise an
  older one without testing on it.
