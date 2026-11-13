#!/usr/bin/env python3
"""lib/cue.py â where in a measured clip each sentence starts.

`pace.py estimate` answers how long a scene will run. This answers the next
question: at what millisecond does the voice reach the sentence a beat is
supposed to land on. It splits the spoken text into sentences and spreads the
measured clip length across them by character count, the same way pace.py fits
its per-voice rate, so the answer costs nothing and needs no new synthesis.

Accurate to a few percent, which is well inside the fade lengths a beat uses.
Where a scene hinges on an exact word, screenshot it with `just peek` instead.

Usage: cue.py <video-dir> [scene_id ...]
"""

import json
import re
import sys
from pathlib import Path

# Chinese writes its stops full-width and puts no space after them, so a
# whitespace-anchored split would return the whole narration as one segment.
SENTENCE = re.compile(r"(?<=[.!?:;])\s+|(?<=[。！？；，])")


def chars(text: str) -> int:
    return len(re.sub(r"[^\w\s]", "", text))


def main() -> int:
    video = Path(sys.argv[1])
    document = json.loads((video / "script.json").read_text(encoding="utf-8"))
    wanted = sys.argv[2:]
    lead = float(document.get("meta", {}).get("lead_silence", 0.0))

    for scene in document["scenes"]:
        sid = scene["id"]
        if wanted and sid not in wanted:
            continue
        dur_file = video / "out" / "audio" / f"{sid}.dur"
        if not dur_file.exists():
            print(f"{sid}: no narration yet â run 'just audio' first", file=sys.stderr)
            continue
        total = float(dur_file.read_text())
        text = (scene.get("tts_text") or scene.get("narration") or "").strip()
        parts = [p for p in SENTENCE.split(text) if p.strip()]
        # The lead silence is real time in the clip but carries no speech, so
        # it is held out of the split and added back as the starting offset.
        spoken = max(total - lead, 0.01)
        weights = [chars(p) for p in parts]
        span = sum(weights) or 1

        print(f"\n{sid}  {total:.1f}s")
        t = lead
        for part, w in zip(parts, weights):
            end = t + spoken * w / span
            print(f"  {int(t * 1000):6d} - {int(end * 1000):6d}  {part}")
            t = end
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
