#!/usr/bin/env bash
# Preflight for a project that does not exist yet.
#
# usage: preflight.sh <project-dir> [github|forgejo|both|none]
#
# Reads and reports; writes nothing. Exits 1 if a [fail] line needs the user's
# attention, 0 when only warnings remain. Run it before `git init`.

set -uo pipefail

name=${1:-}
forge=${2:-github}

if [ -z "$name" ] || [ "$#" -gt 2 ]; then
  echo "usage: preflight.sh <project-dir> [github|forgejo|both|none]" >&2
  exit 2
fi

case "$forge" in
  github | forgejo | both | none) ;;
  *)
    echo "preflight: unknown forge '$forge'" >&2
    exit 2
    ;;
esac

fails=0
warns=0

ok() { printf '[ok]   %s\n' "$*"; }
warn() {
  printf '[warn] %s\n' "$*"
  warns=$((warns + 1))
}
fail() {
  printf '[fail] %s\n' "$*"
  fails=$((fails + 1))
}

echo "preflight: $name (forge: $forge)"
echo

# --- tools -----------------------------------------------------------------
for tool in git nix just; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool $(command -v "$tool")"
  else
    fail "$tool is not on PATH"
  fi
done

if command -v cargo >/dev/null 2>&1; then
  ok "cargo $(command -v cargo)"
else
  warn "cargo is not on PATH; the Nix devshell must supply it"
fi

if [ "$forge" = github ] || [ "$forge" = both ]; then
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      ok "gh is authenticated"
    else
      fail "gh is installed but not authenticated; run 'gh auth login' or choose no remote"
    fi
  else
    fail "gh is not on PATH; install it or choose no remote"
  fi
fi

if [ "$forge" = forgejo ] || [ "$forge" = both ]; then
  if command -v tea >/dev/null 2>&1; then
    ok "tea $(command -v tea)"
  else
    warn "tea is not on PATH; create the Forgejo repository in the web UI instead"
  fi
fi

if command -v nix >/dev/null 2>&1; then
  if nix show-config 2>/dev/null | grep -q '^experimental-features = .*flakes'; then
    ok "Nix has flakes enabled"
  else
    warn "flakes are not enabled in nix.conf; the devshell will not evaluate"
  fi
fi

# --- name ------------------------------------------------------------------
base=$(basename "$name")
if printf '%s' "$base" | grep -qE '^[a-z][a-z0-9-]*$'; then
  ok "name '$base' is a lowercase kebab-case crate and binary name"
else
  warn "name '$base' is not lowercase kebab-case; Cargo accepts it, crates.io may not"
fi

# --- git identity ----------------------------------------------------------
git_name=$(git config --get user.name || true)
git_email=$(git config --get user.email || true)

if [ -n "$git_name" ] && [ -n "$git_email" ]; then
  ok "git identity: $git_name <$git_email>"
else
  fail "git identity is unset; set user.name and user.email, do not let a scaffold invent one"
fi

if printf '%s' "$git_name" | grep -qiE '^(root|user|your name|unknown|changeme)$'; then
  warn "git user.name looks like a placeholder: '$git_name'"
fi

# --- target directory ------------------------------------------------------
if [ -e "$name" ] && [ ! -d "$name" ]; then
  fail "$name exists and is not a directory"
elif [ -d "$name" ]; then
  entries=$(find "$name" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')
  if [ "$entries" -eq 0 ]; then
    ok "$name exists and is empty"
  else
    fail "$name is not empty ($entries entries); choose a new directory or adopt it deliberately"
    find "$name" -mindepth 1 -maxdepth 1 -print | sed 's/^/       /'
  fi
else
  parent=$(dirname "$name")
  if [ -d "$parent" ] && [ -w "$parent" ]; then
    ok "$name does not exist; $parent is writable"
  else
    fail "$parent is missing or not writable"
  fi
fi

# --- remote ----------------------------------------------------------------
case "$forge" in
  github | both)
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      owner=$(gh api user --jq .login 2>/dev/null || true)
      if [ -n "$owner" ]; then
        repo="$owner/$base"
        if gh repo view "$repo" >/dev/null 2>&1; then
          fail "github.com/$repo already exists; pick another name or clone it instead"
        else
          ok "github.com/$repo is free (as far as gh can tell)"
        fi
      else
        warn "could not read the GitHub login; remote collision not checked"
      fi
    else
      warn "GitHub remote collision not checked (gh unavailable or unauthenticated)"
    fi
    ;;
esac

case "$forge" in
  forgejo | both)
    warn "Forgejo remote existence is not checked: an empty repository answers git ls-remote with no refs"
    ;;
esac

echo
if [ "$fails" -gt 0 ]; then
  echo "preflight failed: $fails to fix, $warns warning(s). Nothing was written."
  exit 1
fi

echo "preflight passed with $warns warning(s). Nothing was written."
