#!/usr/bin/env bash
# lib/review.sh — contact sheets of the rendered clips, so the frames can be
# looked at without playing anything. Six evenly spaced frames per scene,
# including the first and the last.
# Usage: review.sh <video-dir> [scene_id ...]
set -euo pipefail

VIDEO="$(cd "${1:?usage: review.sh <video-dir> [scene_id ...]}" && pwd)"
shift
SCRIPT="$VIDEO/script.json"
SAMPLES=6

if [ "$#" -gt 0 ]; then
  ids=("$@")
else
  mapfile -t ids < <(jq -r '.scenes[].id' "$SCRIPT")
fi
# A portrait frame scaled to a fixed width makes a contact sheet taller than it
# is wide. Scale those to a fixed height and lay the six out in one row instead.
read -r RW RH < <(jq -er '[.meta.resolution[0] // 1920,
                           .meta.resolution[1] // 1080] | @tsv' "$SCRIPT")
if [ "$RH" -gt "$RW" ]; then SCALE="-1:640"; TILE="6x1"; else SCALE="640:-1"; TILE="3x2"; fi

mkdir -p "$VIDEO/out/review"

for id in "${ids[@]}"; do
  clip="$VIDEO/out/clips/$id.mp4"
  [ -f "$clip" ] || { echo "missing out/clips/$id.mp4" >&2; exit 1; }
  # nb_frames comes from the container, so this does not decode the clip.
  frames="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=nb_frames -of default=nw=1:nk=1 "$clip")"
  work="$(mktemp -d)"
  for n in $(seq 0 $(( SAMPLES - 1 ))); do
    index=$(( n * (frames - 1) / (SAMPLES - 1) ))
    ffmpeg -y -v error -i "$clip" \
      -vf "select=eq(n\,$index),scale=$SCALE" -frames:v 1 \
      "$work/$(printf '%02d' "$n").png"
  done
  montage "$work"/*.png -tile "$TILE" -geometry +6+6 -background '#202020' \
    "$VIDEO/out/review/$id.png"
  rm -rf "$work"
  echo "out/review/$id.png ($frames frames)"
done
