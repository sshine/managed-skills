#!/usr/bin/env bash
# lib/render.sh — render scene pages to out/clips/<id>.mp4.
#
# Each clip is sized from the narration Kokoro actually produced (out/audio/
# <id>.dur plus a short tail), not from the manuscript's seconds estimate, so
# visuals and speech cannot drift apart.
#
# Usage: render.sh <video-dir> [scene_id ...]
set -euo pipefail

LIB="$(cd "$(dirname "$0")" && pwd)"
VIDEO="$(cd "${1:?usage: render.sh <video-dir> [scene_id ...]}" && pwd)"
shift
SCRIPT="$VIDEO/script.json"
TAIL_SECONDS=0.8

read -r FPS WIDTH HEIGHT CANVAS_W CANVAS_H THEME < <(
  jq -er '[.meta.fps // 30, .meta.resolution[0] // 1920,
           .meta.resolution[1] // 1080, .meta.canvas[0] // 1920,
           .meta.canvas[1] // 1080, .meta.theme // "light"] | @tsv' "$SCRIPT"
)
# .meta.stylesheet is relative to the video directory; the pages sit one below.
STYLESHEET="$(jq -r '.meta.stylesheet // empty | "../" + .' "$SCRIPT")"

if [ "$#" -gt 0 ]; then
  ids=("$@")
else
  mapfile -t ids < <(jq -r '.scenes[].id' "$SCRIPT")
fi

mkdir -p "$VIDEO/out/clips"

render_one() {
  local id="$1" page="$VIDEO/scenes/$id.html" dur="$VIDEO/out/audio/$id.dur"
  [ -f "$page" ] || { echo "$id: no scenes/$id.html" >&2; return 1; }
  [ -f "$dur" ] || { echo "$id: no narration yet — run 'just audio' first" >&2; return 1; }
  local seconds
  seconds="$(awk -v tail="$TAIL_SECONDS" '{printf "%.3f", $1 + tail}' "$dur")"
  node "$LIB/capture.mjs" \
    --page "$page" --seconds "$seconds" --out "$VIDEO/out/clips/$id.mp4" \
    --fps "$FPS" --width "$WIDTH" --height "$HEIGHT" \
    --canvas-w "$CANVAS_W" --canvas-h "$CANVAS_H" --theme "$THEME" \
    ${STYLESHEET:+--css "$STYLESHEET"}
}

# Scenes are independent, and one Chromium plus one x264 does not saturate a
# multi-core box. Cap the fan-out so the machine stays usable while rendering.
JOBS="${JOBS:-$(( $(nproc) / 3 > 1 ? $(nproc) / 3 : 1 ))}"
fail=0
running=0
for id in "${ids[@]}"; do
  render_one "$id" 2>&1 | sed "s/^/[$id] /" &
  running=$(( running + 1 ))
  if [ "$running" -ge "$JOBS" ]; then
    wait -n || fail=1
    running=$(( running - 1 ))
  fi
done
while [ "$running" -gt 0 ]; do
  wait -n || fail=1
  running=$(( running - 1 ))
done
exit "$fail"
