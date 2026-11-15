#!/usr/bin/env bash
#
# Helpers for the bump -> green main CI -> tag -> Release -> pin -> deploy
# sequence. Each subcommand is safe to run on its own; none of them tag a commit
# that main CI has not built successfully.
#
# Usage: release-e2e.sh <command> [options]
# Run `release-e2e.sh --help` for the command list and environment overrides.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: release-e2e.sh <command> [options]

Commands:
  next-version             Print the next minor version (0.(n+1).0).
  bump [VERSION]           Update Cargo versions, run local CI, commit the bump.
                           Options: --skip-ci
  wait-ci                  Poll CI for local HEAD. Refuses if HEAD is not pushed.
  tag vX.Y.Z               Check green main CI, then create and push the tag.
  wait-release vX.Y.Z      Poll the tag-driven Release workflow.
  hashes vX.Y.Z            Print release-hashes output for nix/binary.nix.
  downstream --tag vX.Y.Z  Update the downstream flake, stage flake.lock, switch.
                           Options: --input NAME --binary NAME --downstream DIR
                                    --no-switch
  local-release vX.Y.Z     Build locally and publish with gh after a Release-job
                           failure. Requires a clean checkout at the tag.

Environment:
  REPO, REMOTE, BRANCH, CI_WORKFLOW, RELEASE_WORKFLOW, DOWNSTREAM, INPUT,
  BINARY, POLL_SECONDS, WAIT_SECONDS, VERSION_CMD

Defaults:
  REMOTE=origin BRANCH=main CI_WORKFLOW=ci.yml RELEASE_WORKFLOW=release.yml
  DOWNSTREAM=$HOME/Projects/nixos INPUT=<repo name> BINARY=<input name>
  POLL_SECONDS=20 WAIT_SECONDS=3600

The script never force-pushes a tag. A published tag is immutable.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

say() {
  printf '==> %s\n' "$*"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

has_recipe() {
  command -v just >/dev/null 2>&1 || return 1
  just --list 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside a git repository"
cd "$ROOT"

if [ -z "${REPO:-}" ] && command -v gh >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi
REMOTE=${REMOTE:-origin}
BRANCH=${BRANCH:-main}
CI_WORKFLOW=${CI_WORKFLOW:-ci.yml}
RELEASE_WORKFLOW=${RELEASE_WORKFLOW:-release.yml}
DOWNSTREAM=${DOWNSTREAM:-$HOME/Projects/nixos}
INPUT=${INPUT:-${REPO##*/}}
if [ -z "$INPUT" ]; then
  INPUT=$(basename "$ROOT")
fi
BINARY=${BINARY:-$INPUT}
POLL_SECONDS=${POLL_SECONDS:-20}
WAIT_SECONDS=${WAIT_SECONDS:-3600}

current_version() {
  if [ -n "${VERSION_CMD:-}" ]; then
    eval "$VERSION_CMD"
    return
  fi
  cargo metadata --no-deps --format-version 1 2>/dev/null |
    jq -r '[.packages[] | select(.source == null) | .version] | unique | if length == 1 then .[0] else empty end'
}

next_version() {
  local version major rest minor
  version=$(current_version)
  [ -n "$version" ] || die "could not determine the current version; set VERSION_CMD"
  case "$version" in
    *.*.*) ;;
    *) die "unsupported version format: $version" ;;
  esac
  major=${version%%.*}
  rest=${version#*.}
  minor=${rest%%.*}
  printf '%s.%s.0\n' "$major" "$((minor + 1))"
}

run_local_ci() {
  if [ -f flake.nix ] && command -v nix >/dev/null 2>&1 && has_recipe ci; then
    nix develop -c just ci
  elif has_recipe ci; then
    just ci
  elif command -v cargo >/dev/null 2>&1; then
    cargo test --all-features
  else
    die "no local CI command found (expected 'just ci' or Cargo)"
  fi
}

ensure_synced() {
  [ "$(git branch --show-current)" = "$BRANCH" ] || die "not on $BRANCH"
  git fetch "$REMOTE" "$BRANCH" --quiet
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/$BRANCH")" ] ||
    die "HEAD is not $REMOTE/$BRANCH; push the release commit first"
}

latest_run_for_sha() {
  local workflow sha
  workflow=$1
  sha=$2
  gh run list --workflow "$workflow" --limit 30 \
    --json databaseId,headSha,status,conclusion,url |
    jq -r --arg sha "$sha" \
      '.[] | select(.headSha == $sha) | [.databaseId, .status, (.conclusion // ""), .url] | @tsv' |
    head -n 1
}

wait_for_workflow() {
  local workflow sha label deadline line id status conclusion url
  workflow=$1
  sha=$2
  label=$3
  deadline=$((SECONDS + WAIT_SECONDS))

  while :; do
    line=$(latest_run_for_sha "$workflow" "$sha")
    if [ -n "$line" ]; then
      IFS=$'\t' read -r id status conclusion url <<<"$line"
      case "$status:$conclusion" in
        completed:success)
          say "$label succeeded: $url"
          return 0
          ;;
        completed:*)
          say "$label concluded ${conclusion:-unknown}: $url"
          gh run view "$id" --log-failed || true
          return 1
          ;;
        *)
          say "$label is $status: $url"
          ;;
      esac
    else
      say "waiting for a $label run for $sha"
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      die "timed out after ${WAIT_SECONDS}s waiting for $label"
    fi
    sleep "$POLL_SECONDS"
  done
}

cmd_next_version() {
  need cargo
  need jq
  next_version
}

cmd_bump() {
  need cargo
  need jq
  local version skip_ci tmp
  version=""
  skip_ci=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --skip-ci)
        skip_ci=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        [ -z "$version" ] || die "too many arguments"
        version=$1
        shift
        ;;
    esac
  done

  version=${version:-$(next_version)}
  version=${version#v}
  case "$version" in
    *.*.*) ;;
    *) die "version must be X.Y.Z" ;;
  esac
  [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or stash first"
  if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
    die "tag v$version already exists"
  fi

  if has_recipe bump; then
    just bump "$version"
  else
    [ -f Cargo.toml ] || die "no Cargo.toml and no 'just bump' recipe"
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    awk -v new="$version" '
      /^\[(package|workspace\.package)\]$/ { in_version = 1; print; next }
      /^\[/ { in_version = 0; print; next }
      in_version && /^version = "/ {
        sub(/version = "[^"]+"/, "version = \"" new "\"")
        print
        next
      }
      /path = "crates\// && /version = "/ {
        sub(/version = "[^"]+"/, "version = \"" new "\"")
        print
        next
      }
      { print }
    ' Cargo.toml >"$tmp"
    mv "$tmp" Cargo.toml
    trap - EXIT
  fi

  if [ -f Cargo.toml ]; then
    cargo check --workspace --all-features >/dev/null
  fi
  [ "$skip_ci" -eq 1 ] || run_local_ci

  git add -A
  git commit -m "chore(release): v$version"
  say "committed v$version; next: git push $REMOTE $BRANCH"
}

cmd_wait_ci() {
  need gh
  need jq
  ensure_synced
  wait_for_workflow "$CI_WORKFLOW" "$(git rev-parse HEAD)" "CI"
}

cmd_tag() {
  need gh
  need jq
  local raw tag version sha
  raw=${1:-}
  [ -n "$raw" ] || die "usage: tag vX.Y.Z"
  tag="v${raw#v}"

  [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit first"
  ensure_synced
  git fetch "$REMOTE" --tags --quiet

  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    die "tag $tag already exists locally"
  fi
  if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$tag" >/dev/null 2>&1; then
    die "tag $tag already exists on $REMOTE"
  fi

  version=$(current_version)
  [ "v$version" = "$tag" ] || die "manifest version v$version does not match $tag"

  sha=$(git rev-parse HEAD)
  wait_for_workflow "$CI_WORKFLOW" "$sha" "CI"

  git tag -a "$tag" -m "$tag"
  git push "$REMOTE" "$tag"
  say "pushed $tag; next: wait-release $tag"
}

cmd_wait_release() {
  need gh
  need jq
  local tag sha
  tag="v${1:-}"
  [ "$tag" != "v" ] || die "usage: wait-release vX.Y.Z"
  git fetch "$REMOTE" --tags --quiet
  sha=$(git rev-parse "$tag^{commit}") || die "tag $tag not found; push it first"
  wait_for_workflow "$RELEASE_WORKFLOW" "$sha" "Release"
  gh release view "$tag" --json tagName,url,isDraft,isPrerelease \
    --jq '{tagName, url, isDraft, isPrerelease}'
}

cmd_hashes() {
  local tag
  tag="v${1:-}"
  [ "$tag" != "v" ] || die "usage: hashes vX.Y.Z"
  has_recipe release-hashes || die "no 'just release-hashes' recipe"
  just release-hashes "$tag"
  if [ -f nix/binary.nix ]; then
    say "now update nix/binary.nix, commit 'chore(nix): pin $tag release hashes', and push"
  fi
}

cmd_downstream() {
  need nix
  local tag raw input downstream binary do_switch installed
  tag=""
  input=$INPUT
  downstream=$DOWNSTREAM
  binary=$BINARY
  do_switch=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)
        tag=${2:-}
        shift 2
        ;;
      --input)
        input=${2:-}
        shift 2
        ;;
      --downstream)
        downstream=${2:-}
        shift 2
        ;;
      --binary)
        binary=${2:-}
        shift 2
        ;;
      --no-switch)
        do_switch=0
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done

  [ -n "$tag" ] || die "--tag is required"
  tag="v${tag#v}"
  [ -d "$downstream/.git" ] || die "$downstream is not a git repository"

  cd "$downstream"
  say "updating input $input in $downstream"
  nix flake update "$input"
  git add flake.lock

  if [ "$do_switch" -eq 1 ]; then
    if has_recipe switch; then
      just switch
    else
      sudo nixos-rebuild switch --flake .
    fi
  fi

  installed=$("$binary" --version 2>/dev/null || true)
  say "installed: ${installed:-unknown}"
  case "$installed" in
    *"${tag#v}"*) ;;
    *) die "installed $binary does not report ${tag#v}" ;;
  esac
}

cmd_local_release() {
  need gh
  local tag
  tag="v${1:-}"
  [ "$tag" != "v" ] || die "usage: local-release vX.Y.Z"
  [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit first"

  git rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
    die "tag $tag does not exist; never create a release tag before CI is green"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "$tag^{commit}")" ] ||
    die "check out $tag before building the fallback release"

  if has_recipe dist; then
    just dist "$tag"
  elif has_recipe dist-linux; then
    just dist-linux "$tag"
  else
    die "no 'dist' or 'dist-linux' recipe"
  fi

  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" dist/* --clobber
    gh release edit "$tag" --draft=false
  else
    gh release create "$tag" dist/* --generate-notes
  fi
  say "published local fallback release for $tag"
}

case "${1:-}" in
  next-version)
    shift
    cmd_next_version "$@"
    ;;
  bump)
    shift
    cmd_bump "$@"
    ;;
  wait-ci)
    shift
    cmd_wait_ci "$@"
    ;;
  tag)
    shift
    cmd_tag "$@"
    ;;
  wait-release)
    shift
    cmd_wait_release "$@"
    ;;
  hashes)
    shift
    cmd_hashes "$@"
    ;;
  downstream)
    shift
    cmd_downstream "$@"
    ;;
  local-release)
    shift
    cmd_local_release "$@"
    ;;
  "" | -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
