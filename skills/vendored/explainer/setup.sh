#!/usr/bin/env bash
# Install or refresh the workspace tooling in a directory. Re-running upgrades
# the tools; a video's own script.json, scenes/ and out/ are never touched.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/workspace" && pwd)"
DEST="${1:?usage: setup.sh <workspace-dir>}"
mkdir -p "$DEST"
for path in flake.nix flake.lock Justfile .gitignore nix lib template; do
  rm -rf "${DEST:?}/$path"
  cp -r "$SRC/$path" "$DEST/$path"
done
echo "workspace tooling installed in $DEST"
