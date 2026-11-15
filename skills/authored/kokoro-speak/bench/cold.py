#!/usr/bin/env python3
"""Time a fresh `kokoro-speak` process, model load included.

The warm benchmark in bench.py loads the model once and measures synthesis.
This script measures what a user actually waits for when the command runs and
exits: Python start, model load, provider setup, synthesis and WAV write.

    nix run .#kokoro-bench-cpu -- --help        # warm benchmark
    python3 bench/cold.py --wrapper result/bin/kokoro-speak --text "Hello."
"""

import argparse
import json
import statistics
import subprocess
import tempfile
import time
import wave
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wrapper", required=True, help="path to kokoro-speak")
    parser.add_argument("--label", default="cold")
    parser.add_argument("--text", default="The build finished on all three hosts.")
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default=None)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="kokoro-cold-") as temporary:
        output = Path(temporary) / "speech.wav"
        command = [args.wrapper, "--out", str(output), "--no-play"]
        if args.device:
            command += ["--device", args.device]
        command.append(args.text)

        times = []
        for _ in range(args.runs):
            t0 = time.perf_counter()
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            times.append(time.perf_counter() - t0)

        with wave.open(str(output)) as wav:
            audio_s = wav.getnframes() / wav.getframerate()

    result = {
        "label": args.label,
        "text": args.text,
        "words": len(args.text.split()),
        "audio_s": round(audio_s, 3),
        "runs": args.runs,
        "cold_median_s": round(statistics.median(times), 3),
        "cold_min_s": round(min(times), 3),
        "cold_max_s": round(max(times), 3),
        "x_realtime_including_startup": round(audio_s / statistics.median(times), 2),
    }
    print(json.dumps(result, indent=2))
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
