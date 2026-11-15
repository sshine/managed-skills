# Release recipes.
#
# Appended to the existing justfile, not a replacement: everything above this marker is
# yours already, and the recipe names below are the ones the release workflow calls.
# `just --list` shows them beside the CI verbs.
#
# Replace `example` with the crate that the tag names. Every workspace member inherits
# [workspace.package].version, so one `cargo pkgid` is enough to compare the tag against
# the version cargo would publish.
#
# If the crate and the binary are named differently, `tar` and `install` need the binary's
# name; everything else here names the crate. If macOS is not a release target, drop
# `macos_target` from the two hash loops and delete the `macos` job from the workflow.

crate := "example"
release_repo := "sshine/example"
release_targets := "x86_64-unknown-linux-musl aarch64-unknown-linux-musl"
macos_target := "aarch64-apple-darwin"

# The CI workflow whose latest run on main must be green before tagging. Use the file
# name, not the display name; `gh run list --workflow` accepts either, but the file name
# survives a title edit. The standard layout calls it ci.yml.
ci_workflow := "ci.yml"

# The URL the `tag` recipe prints when it cannot read CI state itself.
# Forgejo: "https://git.example.com/owner/example/actions?query=branch%3Amain".
ci_url := "https://github.com/sshine/example/actions?query=branch%3Amain"

# ---------------------------------------------------------------------------
# Version and artifacts
# ---------------------------------------------------------------------------

# Assert the release tag names the version cargo would publish
check-version version:
    @pkgid="$(cargo pkgid -p {{crate}})"; crate="v${pkgid##*#}"; \
    if [ "$crate" != "{{version}}" ]; then \
        echo "tag {{version}} does not match crate version $crate" >&2; exit 1; \
    fi

# A matrix leg calls this for the one target it was given; the leg starts from an empty
# checkout, so the append is a no-op there. Locally it is what lets a second target be
# added without rebuilding the first.
#
# Build one target into dist/ without clearing it
dist-target version target: (check-version version)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p dist
    cargo build --release --locked --target "{{target}}" -p {{crate}}
    name="{{crate}}-{{version}}-{{target}}"
    tar -czf "dist/$name.tar.gz" -C "target/{{target}}/release" {{crate}}
    ( cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )

# The tarball name carries the target triple because nothing inside the archive says
# which architecture it is until the loader fails. The version in the name is the tag
# verbatim, `v` included, because nix/binary.nix builds the download URL from the tag.
#
# Build the static release artifacts and their checksums into dist/
dist-linux version: (check-version version)
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf dist && mkdir -p dist
    for target in {{release_targets}}; do
        just dist-target "{{version}}" "$target"
    done
    ls -1 dist

# macOS binaries are not static: they link libSystem and the system frameworks, so the
# archive is a normal dynamic executable. Building the target on a Linux host needs the
# macOS SDK, which is not redistributable; the native runner has it already.
#
# Build the macOS aarch64 tarball on a Mac
dist-macos version: (check-version version)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p dist
    # A no-op when rust-toolchain.toml already lists the target, which it should.
    rustup target add {{macos_target}}
    cargo build --release --locked --target {{macos_target}} -p {{crate}}
    name="{{crate}}-{{version}}-{{macos_target}}"
    tar -czf "dist/$name.tar.gz" -C "target/{{macos_target}}/release" {{crate}}
    # macOS ships shasum, not sha256sum; the sidecar is the same format.
    ( cd dist && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256" )
    ls -1 dist

# Local builds are not bit-identical to the ones CI publishes, so hashing dist/ would
# give values that never match what fetchurl downloads. This reads the tarball the
# release actually serves.
#
# Print the SRI hashes nix/binary.nix pins, read from the published release
release-hashes version:
    #!/usr/bin/env bash
    set -euo pipefail
    for target in {{release_targets}} {{macos_target}}; do
        case "$target" in
            *-apple-darwin) system="aarch64-darwin" ;;
            x86_64-*) system="x86_64-linux" ;;
            aarch64-*) system="aarch64-linux" ;;
            *) echo "no Nix system name for $target" >&2; exit 1 ;;
        esac
        url="https://github.com/{{release_repo}}/releases/download/{{version}}/{{crate}}-{{version}}-$target.tar.gz"
        hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"
        printf '"%s" = "%s";\n' "$system" "$hash"
    done

# Only right when dist/ holds the bytes the release published: download the assets
# first. A locally compiled tarball gives a hash fetchurl will reject.
#
# Print the same SRI lines from a local dist/, for an offline check
dist-hashes:
    #!/usr/bin/env bash
    set -euo pipefail
    for target in {{release_targets}} {{macos_target}}; do
        case "$target" in
            *-apple-darwin) system="aarch64-darwin" ;;
            x86_64-*) system="x86_64-linux" ;;
            aarch64-*) system="aarch64-linux" ;;
            *) echo "no Nix system name for $target" >&2; exit 1 ;;
        esac
        archive=(dist/{{crate}}-*-"$target".tar.gz)
        if [ ! -e "${archive[0]}" ]; then
            echo "no tarball for $target in dist/" >&2
            exit 1
        fi
        hash="$(nix hash file --sri --type sha256 "${archive[0]}")"
        printf '"%s" = "%s";\n' "$system" "$hash"
    done

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

# Refuses unless the tree is clean, HEAD is exactly origin/main, the tag exists neither
# locally nor on origin, and the manifest carries {{version}}. Then it requires the CI
# workflow's latest run on main to be green: a tag pushed before that starts a second job
# that competes for the same Nix cache key instead of restoring it, so both compile and
# neither saves. HEAD must be the commit that run built, not merely an ancestor of it.
#
# Tag the current commit and push the tag, which is what starts the release
tag version: (check-version version)
    #!/usr/bin/env bash
    set -euo pipefail
    tag="{{version}}"

    if [ -n "$(git status --porcelain)" ]; then
        echo "working tree is dirty; commit or stash first" >&2
        exit 1
    fi
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
        echo "not on main; a release tag names a commit on main" >&2
        exit 1
    fi

    git fetch --quiet origin main
    git fetch --quiet --tags origin
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "HEAD is not origin/main; push main, or check out the commit main points at" >&2
        exit 1
    fi
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        echo "tag $tag already exists locally" >&2
        exit 1
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
        echo "tag $tag already exists on origin" >&2
        exit 1
    fi

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        conclusion="$(gh run list --branch main --workflow "{{ci_workflow}}" --limit 1 --json conclusion --jq '.[0].conclusion // ""')"
        if [ "$conclusion" != "success" ]; then
            echo "the latest run on main concluded '${conclusion:-none}'; wait for green:" >&2
            gh run list --branch main --limit 5
            exit 1
        fi
    elif [ "${CONFIRM:-}" != "green" ]; then
        echo "gh is not available, so main's CI state cannot be read." >&2
        echo "Check {{ci_url}} and rerun with CONFIRM=green." >&2
        exit 1
    fi

    git tag -a "$tag" -m "$tag"
    git push origin "$tag"

# ---------------------------------------------------------------------------
# Optional: GUI projects only
# ---------------------------------------------------------------------------
#
# Delete this block unless the project ships a GTK/Qt/Tauri application. A static musl
# build of a toolkit application is not a thing that exists; the AppImage keeps the
# dynamic links and carries the runtime closure instead. It expects nix/appimage.nix and
# a package named example-appimage.

# Build the application as a single-file AppImage for the host architecture
appimage version: (check-version version)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p dist
    nix build .#example-appimage
    name="{{crate}}-{{version}}-$(uname -m).AppImage"
    cp -fL result "dist/$name"
    ( cd dist && sha256sum "$name" > "$name.sha256" )
    ls -1 dist
