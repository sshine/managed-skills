#!/usr/bin/env python3
"""lib/tts.py — synthesize scene narration with Kokoro-82M, offline.

Writes out/audio/<id>.wav at Kokoro's native 24 kHz plus an <id>.dur sidecar
holding the clip length in seconds, which is what sizes the rendered visuals.
An <id>.key sidecar records the voice, speed and exact spoken text, so a rerun
re-synthesizes only the scenes whose speech actually changed.

Kokoro clips the very start of an utterance, so `lead_silence` seconds of quiet
are prepended: set it in .meta for every scene, or per scene to override. It is
counted into the .dur sidecar, so a scene page's clock still starts at the frame
the clip does, and beats stay written against one timeline.

Usage: tts.py --script SCRIPT --out OUTDIR [--force] [scene_id ...]
"""

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_VOICE = "af_heart"
DEFAULT_SPEED = 1.0
DEFAULT_LEAD_SILENCE = 0.0

# Kokoro names a voice for the language it was trained on, and the first letter
# is that language. Deriving the phonemizer's code from it means a Chinese
# voice needs nothing but .meta.voice; .meta.lang overrides when espeak wants
# a different variant than the default below (en-gb for a British voice, say).
VOICE_LANG = {
    "a": "en-us", "b": "en-gb", "e": "es", "f": "fr-fr", "h": "hi",
    "i": "it", "j": "ja", "p": "pt-br", "z": "cmn",
}


def language(meta: dict, voice: str) -> str:
    lang = meta.get("lang")
    if lang:
        return lang
    code = VOICE_LANG.get(voice[:1])
    if not code:
        die(f"cannot tell the language of voice {voice!r}; set .meta.lang")
    return code


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def spoken_text(scene: dict) -> str:
    """What the voice says: tts_text overrides narration for pronunciation."""
    text = (scene.get("tts_text") or scene.get("narration") or "").strip()
    if not text:
        die(f"scene {scene.get('id')!r} has no narration")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("scenes", nargs="*")
    args = parser.parse_args()

    document = json.loads(args.script.read_text(encoding="utf-8"))
    meta = document.get("meta", {})
    voice = meta.get("voice", DEFAULT_VOICE)
    lang = language(meta, voice)
    speed = float(meta.get("speed", DEFAULT_SPEED))
    lead_default = float(meta.get("lead_silence", DEFAULT_LEAD_SILENCE))
    by_id = {scene["id"]: scene for scene in document["scenes"]}
    ids = args.scenes or list(by_id)
    for sid in ids:
        if sid not in by_id:
            die(f"no scene {sid!r} in {args.script}")

    args.out.mkdir(parents=True, exist_ok=True)
    work = []
    for sid in ids:
        text = spoken_text(by_id[sid])
        lead = float(by_id[sid].get("lead_silence", lead_default))
        key = f"{voice}\n{lang}\n{speed}\n{lead}\n{text}\n"
        key_path = args.out / f"{sid}.key"
        fresh = (
            not args.force
            and (args.out / f"{sid}.wav").exists()
            and (args.out / f"{sid}.dur").exists()
            and key_path.exists()
            and key_path.read_text(encoding="utf-8") == key
        )
        if fresh:
            print(f"{sid}: unchanged")
        else:
            work.append((sid, text, lead, key))
    if not work:
        return

    model_dir = Path(os.environ.get("KOKORO_MODEL_DIR", ""))
    lib = os.environ.get("ESPEAK_LIBRARY", "")
    if not model_dir.is_dir() or not os.path.exists(lib):
        die("Kokoro is not on the environment — run inside 'nix develop'.")

    import numpy
    import soundfile
    from kokoro_onnx import Kokoro
    from kokoro_onnx.config import EspeakConfig

    kokoro = Kokoro(
        str(model_dir / "kokoro-v1.0.onnx"),
        str(model_dir / "voices-v1.0.bin"),
        espeak_config=EspeakConfig(
            lib_path=lib, data_path=os.environ.get("ESPEAK_DATA_PATH")
        ),
    )
    for sid, text, lead, key in work:
        samples, rate = kokoro.create(text, voice=voice, speed=speed, lang=lang)
        if lead > 0:
            quiet = numpy.zeros(int(lead * rate), dtype=samples.dtype)
            samples = numpy.concatenate([quiet, samples])
        soundfile.write(args.out / f"{sid}.wav", samples, rate)
        seconds = len(samples) / rate
        (args.out / f"{sid}.dur").write_text(f"{seconds:.3f}\n", encoding="utf-8")
        (args.out / f"{sid}.key").write_text(key, encoding="utf-8")
        print(f"{sid}: {seconds:.1f}s")


if __name__ == "__main__":
    main()
