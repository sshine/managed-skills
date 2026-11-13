#!/usr/bin/env bash
# lib/check.sh — manuscript and scene-page sanity, before anything long runs.
# Usage: check.sh <video-dir>
set -euo pipefail

VIDEO="$(cd "${1:?usage: check.sh <video-dir>}" && pwd)"
SCRIPT="$VIDEO/script.json"
[ -f "$SCRIPT" ] || { echo "no script.json in $VIDEO" >&2; exit 1; }

jq -r '
  def fail($m): ($m + "\n") | halt_error(1);
  (.meta // fail("script.json has no .meta")) as $m
  | (.scenes // fail("script.json has no .scenes")) as $s
  | if ($s | type) != "array" or ($s | length) == 0 then fail(".scenes must be a non-empty array") else . end
  | if ($m.fps // 30 | floor != . or . <= 0) then fail(".meta.fps must be a positive integer") else . end
  | (($m.resolution // [1920, 1080])) as $r
  | (($m.canvas // [1920, 1080])) as $c
  | if ($r | length) != 2 or ($r | map(floor != . or . <= 0 or . % 2 == 1) | any)
    then fail(".meta.resolution must be two positive even numbers") else . end
  | if ($c | length) != 2 or ($c | map(floor != . or . <= 0) | any)
    then fail(".meta.canvas must be two positive numbers") else . end
  | if $r[0] * $c[1] != $r[1] * $c[0]
    then fail(".meta.resolution and .meta.canvas must share an aspect ratio")
    else . end
  | ($s | map(.id)) as $ids
  | ($ids | map(select(test("^s[0-9]+_[a-z0-9_]+$") | not))) as $bad
  | if ($bad | length) > 0 then fail("scene ids must look like s1_slug: \($bad | join(", "))") else . end
  | if ($ids | unique | length) != ($ids | length) then fail("duplicate scene ids") else . end
  | ($s | map(select((.narration // "") == ""))| map(.id)) as $silent
  | if ($silent | length) > 0 then fail("no narration: \($silent | join(", "))") else . end
  | empty' "$SCRIPT"

missing=()
while read -r id; do
  [ -f "$VIDEO/scenes/$id.html" ] || missing+=("$id")
done < <(jq -r '.scenes[].id' "$SCRIPT")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "no scene page yet for: ${missing[*]}" >&2
  echo "copy ../template/scene.html to scenes/<id>.html" >&2
  exit 1
fi

echo "$(basename "$VIDEO"): $(jq -r '.scenes | length' "$SCRIPT") scenes, manuscript ok"
