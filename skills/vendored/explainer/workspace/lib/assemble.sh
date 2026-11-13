#!/usr/bin/env bash
# lib/assemble.sh — mux the per-scene clips with their narration into one mp4.
#
# The clips are already final H.264 and are stream-copied; only the narration is
# encoded, padded to each clip's length so a scene never cuts its own speech off.
# Usage: assemble.sh <video-dir>
set -euo pipefail

VIDEO="$(cd "${1:?usage: assemble.sh <video-dir>}" && pwd)"
SCRIPT="$VIDEO/script.json"
NAME="$(basename "$VIDEO")"
OUT="$VIDEO/out/$NAME.mp4"

read -r FPS WIDTH HEIGHT < <(
  jq -er '[.meta.fps // 30, .meta.resolution[0] // 1920,
           .meta.resolution[1] // 1080] | @tsv' "$SCRIPT"
)
mapfile -t ids < <(jq -r '.scenes[].id' "$SCRIPT")

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/list.txt"

for id in "${ids[@]}"; do
  clip="$VIDEO/out/clips/$id.mp4"
  wav="$VIDEO/out/audio/$id.wav"
  [ -f "$clip" ] || { echo "missing out/clips/$id.mp4 — run 'just render'" >&2; exit 1; }
  [ -f "$wav" ] || { echo "missing out/audio/$id.wav — run 'just audio'" >&2; exit 1; }
  # 2 dB of headroom leaves room for AAC to overshoot without clipping.
  ffmpeg -y -v error -i "$clip" -i "$wav" \
    -map 0:v:0 -map 1:a:0 -af 'volume=-2dB,apad' -shortest \
    -c:v copy -c:a aac -b:a 192k -map_metadata -1 "$WORK/$id.mp4"
  printf "file '%s'\n" "$WORK/$id.mp4" >> "$WORK/list.txt"
done

ffmpeg -y -v error -f concat -safe 0 -i "$WORK/list.txt" \
  -c copy -map_metadata -1 -movflags +faststart "$WORK/final.mp4"

# One cheap probe: the shape a finished cut has to have. It says nothing about
# whether the video is any good — watch it.
probe="$(ffprobe -v error -show_entries \
  'stream=codec_type,codec_name,width,height,r_frame_rate:format=duration' \
  -of json "$WORK/final.mp4")"
jq -r --argjson fps "$FPS" --argjson w "$WIDTH" --argjson h "$HEIGHT" '
  [.streams[] | select(.codec_type == "video")] as $video |
  [.streams[] | select(.codec_type == "audio")] as $audio |
  $video[0] as $v |
  if   ($video | length) != 1 then "expected exactly one video stream"
  elif ($audio | length) != 1 then "expected exactly one audio stream"
  elif $v.codec_name != "h264" then "video is \($v.codec_name), expected h264"
  elif $v.width != $w or $v.height != $h then
    "video is \($v.width)x\($v.height), expected \($w)x\($h)"
  elif ($v.r_frame_rate | split("/") | (.[0] | tonumber) / (.[1] | tonumber)) != $fps then
    "video is \($v.r_frame_rate)fps, expected \($fps)"
  else empty end
  | . + "\n" | halt_error(1)' <<<"$probe"

mv -f "$WORK/final.mp4" "$OUT"
printf '%s  %ss  %sx%s @ %sfps\n' "$OUT" \
  "$(jq -r '.format.duration | tonumber | floor' <<<"$probe")" "$WIDTH" "$HEIGHT" "$FPS"
