#!/usr/bin/env python3
"""Time Kokoro-82M synthesis at several text lengths.

Run it through one of the skill's `kokoro-bench` packages, which set the model
and espeak paths:

    nix run .#kokoro-bench     -- --label cpu
    nix run .#kokoro-bench-cuda -- --label cuda

The script loads the model once, then reports warm synthesis time for each
length. That separates the cost of the model load (a constant per process)
from the cost of synthesis, which is what changes with text length.
"""

import argparse
import json
import os
import statistics
import time
from pathlib import Path

MODEL_DIR = Path(os.environ["KOKORO_MODEL_DIR"])
ESPEAK_LIB = os.environ["ESPEAK_LIBRARY"]
ESPEAK_DATA = os.environ.get("ESPEAK_DATA_PATH") or None

BASE = (
    "Kokoro is a compact text to speech model. It turns written language into "
    "natural sounding speech on ordinary hardware. The model is small enough "
    "to run locally, without a network connection or an account. A short "
    "sentence takes a fraction of a second, and a long report takes a little "
    "longer, but the voice stays the same. "
)
WORDS = BASE.split()


def text_for(words: int) -> str:
    """Repeat BASE until there are at least `words` words, then trim."""
    if words <= 0:
        raise ValueError("words must be positive")
    out = []
    while len(out) < words:
        out.extend(WORDS[: words - len(out)])
    return " ".join(out).rstrip(",;:") + "."


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", default="cpu", help="name for this run")
    parser.add_argument(
        "--lengths",
        default="5,20,50,100,300,1000",
        help="comma-separated word counts (default: 5,20,50,100,300,1000)",
    )
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument(
        "--device",
        choices=("auto", "cpu", "cuda"),
        default="auto",
        help="execution provider; auto uses the wrapper's ONNX_PROVIDER",
    )
    parser.add_argument(
        "--repeat",
        type=int,
        default=3,
        help="measured runs per short length (default: 3)",
    )
    parser.add_argument(
        "--repeat-long",
        type=int,
        default=1,
        help="measured runs per long length (default: 1)",
    )
    parser.add_argument(
        "--long-threshold",
        type=int,
        default=500,
        help="word count at which --repeat-long applies (default: 500)",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    import numpy  # noqa: F401  (imported for the package to be exercised)
    import onnxruntime
    from kokoro_onnx import Kokoro
    from kokoro_onnx.config import EspeakConfig

    if args.device == "cpu":
        os.environ["ONNX_PROVIDER"] = "CPUExecutionProvider"
    elif args.device == "cuda":
        os.environ["ONNX_PROVIDER"] = "CUDAExecutionProvider"

    started = time.perf_counter()
    kokoro = Kokoro(
        str(MODEL_DIR / "kokoro-v1.0.onnx"),
        str(MODEL_DIR / "voices-v1.0.bin"),
        espeak_config=EspeakConfig(lib_path=ESPEAK_LIB, data_path=ESPEAK_DATA),
    )
    load_s = time.perf_counter() - started

    rows = []
    for words in [int(x) for x in args.lengths.split(",")]:
        text = text_for(words)
        repeats = args.repeat_long if words >= args.long_threshold else args.repeat

        # The first inference through a shape pays provider setup and kernel
        # selection, so every length gets a warm-up before the measured runs.
        samples, rate = kokoro.create(
            text, voice=args.voice, speed=args.speed, lang="en-us"
        )
        audio_s = len(samples) / rate

        # Phonemization is CPU-only and single-threaded; it is the ceiling on
        # GPU speed-up at long lengths.
        t0 = time.perf_counter()
        kokoro.tokenizer.phonemize(text, "en-us")
        phonemize_s = time.perf_counter() - t0

        times = []
        for _ in range(repeats):
            t0 = time.perf_counter()
            samples, rate = kokoro.create(
                text, voice=args.voice, speed=args.speed, lang="en-us"
            )
            times.append(time.perf_counter() - t0)
        audio_s = len(samples) / rate
        median = statistics.median(times)

        row = {
            "label": args.label,
            "words": words,
            "chars": len(text),
            "audio_s": round(audio_s, 3),
            "phonemize_s": round(phonemize_s, 3),
            "repeats": repeats,
            "synth_median_s": round(median, 3),
            "synth_min_s": round(min(times), 3),
            "synth_max_s": round(max(times), 3),
            "rtf": round(median / audio_s, 4),
            "x_realtime": round(audio_s / median, 2),
        }
        rows.append(row)
        print(json.dumps(row), flush=True)

    result = {
        "label": args.label,
        "voice": args.voice,
        "speed": args.speed,
        "device": args.device,
        "providers": kokoro.sess.get_providers(),
        "available_providers": onnxruntime.get_available_providers(),
        "onnxruntime": onnxruntime.__version__,
        "load_s": round(load_s, 3),
        "rows": rows,
    }
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
