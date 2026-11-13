#!/usr/bin/env bash
# lib/audition.sh — play each scene's synthesized narration while printing what
# it is meant to say, so pronunciation and pacing get heard before any rendering.
# Usage: audition.sh <video-dir> [scene_id ...]
set -euo pipefail

VIDEO="$(cd "${1:?usage: audition.sh <video-dir> [scene_id ...]}" && pwd)"
shift
SCRIPT="$VIDEO/script.json"

if [ "$#" -gt 0 ]; then
  ids=("$@")
else
  mapfile -t ids < <(jq -r '.scenes[].id' "$SCRIPT")
fi

for id in "${ids[@]}"; do
  wav="$VIDEO/out/audio/$id.wav"
  [ -f "$wav" ] || { echo "no narration for $id — run 'just audio'" >&2; exit 1; }
  printf '\n\033[1m%s\033[0m  (%ss)\n' "$id" "$(cat "$VIDEO/out/audio/$id.dur")"
  jq -r --arg id "$id" '.scenes[] | select(.id == $id)
    | "  narration: \(.narration)"
    + (if .tts_text then "\n  spoken:    \(.tts_text)" else "" end)' "$SCRIPT"
  ffplay -v error -nodisp -autoexit "$wav"
done
