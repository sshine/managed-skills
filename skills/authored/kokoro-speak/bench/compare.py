#!/usr/bin/env python3
"""Turn two `kokoro-bench --json-out` files into a Markdown comparison."""

import argparse
import json
import math
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cpu", type=Path)
    parser.add_argument("gpu", type=Path)
    parser.add_argument("--cpu-name", default="CPU")
    parser.add_argument("--gpu-name", default="GPU")
    args = parser.parse_args()

    cpu = json.loads(args.cpu.read_text())
    gpu = json.loads(args.gpu.read_text())
    cpu_rows = {row["words"]: row for row in cpu["rows"]}
    gpu_rows = {row["words"]: row for row in gpu["rows"]}

    print(f"CPU: {args.cpu_name} — providers {', '.join(cpu['providers'])}")
    print(f"GPU: {args.gpu_name} — providers {', '.join(gpu['providers'])}")
    print()
    print(
        "| Words | Audio | Phonemize | CPU synth | GPU synth | Speed-up | "
        "CPU xRT | GPU xRT |"
    )
    print("|---:|---:|---:|---:|---:|---:|---:|---:|")
    speedups = []
    for words in sorted(cpu_rows):
        c = cpu_rows[words]
        g = gpu_rows[words]
        speedup = c["synth_median_s"] / g["synth_median_s"]
        speedups.append(speedup)
        print(
            f"| {words} | {c['audio_s']:.1f} s | {c['phonemize_s']:.2f} s | "
            f"{c['synth_median_s']:.2f} s | {g['synth_median_s']:.2f} s | "
            f"{speedup:.2f}x | {c['x_realtime']:.2f}x | {g['x_realtime']:.2f}x |"
        )
    print()
    print(f"Model load: CPU {cpu['load_s']:.2f} s, GPU {gpu['load_s']:.2f} s")
    print(
        f"Geometric mean speed-up: "
        f"{math.exp(sum(math.log(s) for s in speedups) / len(speedups)):.2f}x"
    )


if __name__ == "__main__":
    main()
