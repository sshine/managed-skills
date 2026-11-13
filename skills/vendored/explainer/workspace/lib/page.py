#!/usr/bin/env python3
"""lib/page.py — export a video as an explainer page instead of an mp4.

Nothing is captured. The scene pages are copied as they are, the narration is
joined into one mp3 that runs exactly as long as the video would, and
lib/page/player.js plays the pages live with that mp3 as their clock.

The result is one self-contained directory that can be dropped anywhere a web
server serves static files:

    manifest.json   scene order, start times, transcript cues
    narration.mp3
    player.js  player.css  index.html (the explainer on a page of its own)
    lib/            scene.css clock.js anim.js, and theme.css if one is given
    scenes/         the scene pages, plus whatever they load from beside them
    <asset>         anything a scene loads from the video directory as ../<asset>

Usage: page.py <video-dir> <dest-dir> [--css FILE]

--css lays a stylesheet over lib/scene.css in every scene, so the scenes take
on the colours and type of the site they are embedded in. Without it the
video's own .meta.stylesheet is used, if it has one.
"""

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# cue.py is a sibling script, not a package; importing it must not leave a
# __pycache__ behind in lib/, which skill-diff would report.
sys.dont_write_bytecode = True
from cue import SENTENCE, chars  # noqa: E402

LIB = Path(__file__).resolve().parent
# Must equal TAIL_SECONDS in render.sh, so a page runs exactly as long as its video.
TAIL_SECONDS = 0.8
# A scene loads its own siblings by bare name and video-level assets as ../x;
# ../../lib/ is the shared tooling, which moves to lib/ in an export.
SIBLING_REF = re.compile(r"""(?:src|href)=["']\.\./(?!\.\./)([^"'?#]+)["']""")


def cues(scene: dict, start_ms: int, length: float, lead: float) -> list[dict]:
    # The transcript shows what the reader should read, so it splits the
    # narration, not the respelled tts_text; their timings differ by a few
    # percent, which is less than a sentence highlight can show.
    text = (scene.get("narration") or "").strip()
    parts = [p.strip() for p in SENTENCE.split(text) if p.strip()]
    spoken = max(length - TAIL_SECONDS - lead, 0.01)
    weights = [max(chars(p), 1) for p in parts]
    span = sum(weights)
    out, t = [], lead
    for part, w in zip(parts, weights):
        out.append({"at": start_ms + round(t * 1000), "text": part})
        t += spoken * w / span
    return out


def narration(video: Path, ids: list[str], lengths: list[float], dest: Path) -> None:
    # Each clip is padded to its scene's full length, as assemble.sh does, so the
    # joined track stays in step with the scene boundaries in the manifest.
    inputs, chains = [], []
    for i, (sid, length) in enumerate(zip(ids, lengths)):
        inputs += ["-i", str(video / "out" / "audio" / f"{sid}.wav")]
        chains.append(f"[{i}:a]apad=whole_dur={length:.3f},atrim=0:{length:.3f}[a{i}]")
    graph = ";".join(chains) + ";" + "".join(f"[a{i}]" for i in range(len(ids)))
    graph += f"concat=n={len(ids)}:v=0:a=1,volume=-2dB[out]"
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", graph,
         "-map", "[out]", "-ac", "1", "-c:a", "libmp3lame", "-b:a", "64k",
         "-map_metadata", "-1", str(dest)],
        check=True,
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video", type=Path)
    ap.add_argument("dest", type=Path)
    ap.add_argument("--css", type=Path, help="stylesheet laid over lib/scene.css in every scene")
    args = ap.parse_args()

    video = args.video.resolve()
    dest = args.dest.expanduser().resolve()
    document = json.loads((video / "script.json").read_text(encoding="utf-8"))
    meta = document.get("meta", {})
    scenes = document["scenes"]
    ids = [s["id"] for s in scenes]

    # The destination is replaced wholesale, so it must be empty or an earlier
    # export; anything else is more likely a typo than a target.
    if dest.exists() and any(dest.iterdir()) and not (dest / "manifest.json").exists():
        print(f"{dest} is not empty and holds no earlier export; refusing to replace it", file=sys.stderr)
        return 1

    lengths = []
    for sid in ids:
        dur = video / "out" / "audio" / f"{sid}.dur"
        if not dur.exists():
            print(f"{sid}: no narration yet, run 'just audio' first", file=sys.stderr)
            return 1
        lengths.append(float(dur.read_text()) + TAIL_SECONDS)

    css = args.css.expanduser().resolve() if args.css else None
    if css is None and meta.get("stylesheet"):
        css = (video / meta["stylesheet"]).resolve()
    if css is not None and not css.is_file():
        print(f"no stylesheet at {css}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(dir=dest.parent if dest.parent.exists() else None) as tmp:
        out = Path(tmp) / "page"
        (out / "lib").mkdir(parents=True)
        for name in ("scene.css", "clock.js", "anim.js"):
            shutil.copy2(LIB / name, out / "lib" / name)
        for name in ("player.js", "player.css"):
            shutil.copy2(LIB / "page" / name, out / name)
        if css is not None:
            shutil.copy2(css, out / "lib" / "theme.css")

        shutil.copytree(video / "scenes", out / "scenes")
        assets = set()
        for page in (out / "scenes").glob("*.html"):
            text = page.read_text(encoding="utf-8")
            assets.update(SIBLING_REF.findall(text))
            page.write_text(text.replace("../../lib/", "../lib/"), encoding="utf-8")
        for asset in sorted(assets):
            src = video / asset
            if not src.exists():
                print(f"warning: a scene loads ../{asset}, which does not exist", file=sys.stderr)
                continue
            (out / asset).parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir():
                shutil.copytree(src, out / asset)
            else:
                shutil.copy2(src, out / asset)

        narration(video, ids, lengths, out / "narration.mp3")

        lead_default = float(meta.get("lead_silence", 0.0))
        entries, start = [], 0
        for scene, length in zip(scenes, lengths):
            start_ms = start
            ms = round(length * 1000)
            lead = float(scene.get("lead_silence", lead_default))
            entries.append({
                "id": scene["id"],
                "title": scene.get("title", scene["id"]),
                "page": f"scenes/{scene['id']}.html",
                "start": start_ms,
                "duration": ms,
                "cues": cues(scene, start_ms, length, lead),
            })
            start += ms

        manifest = {
            "title": meta.get("title", video.name),
            "canvas": meta.get("canvas", [1920, 1080]),
            "theme": meta.get("theme", "light"),
            "audio": "narration.mp3",
            "duration": start,
            "scenes": entries,
        }
        # Resolved by clock.js relative to each scene page.
        if css is not None:
            manifest["stylesheet"] = "../lib/theme.css"
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        standalone = (LIB / "page" / "standalone.html").read_text(encoding="utf-8")
        (out / "index.html").write_text(standalone.replace("{{title}}", html.escape(manifest["title"])), encoding="utf-8")

        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(out), dest)

    total = start / 1000
    print(f"{dest}  {len(scenes)} scenes  {int(total // 60)}:{int(total % 60):02d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
