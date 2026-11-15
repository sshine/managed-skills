---
name: kokoro-speak
description: >-
  Install Kokoro-82M as an offline text-to-speech command on a NixOS or
  numtide/system-manager machine. The skill vendors the model, the Python
  wheels nixpkgs lacks, an espeak-ng and audio-player wrapper, and a
  flake-parts module whose settings become NixOS/system-manager options, so
  text piped on stdin is spoken locally with no cloud and no API key. The
  package can be built with the CUDA execution provider for an NVIDIA GPU.
  Use when asked to make a computer talk, add local TTS, install Kokoro, read
  text or an agent's final response aloud, or package a speech command for a
  Nix system.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
user-invocable: true
---

# kokoro-speak — Kokoro-82M on the system

The outcome is one command that needs nothing but text on stdin:

```bash
echo "The build finished." | kokoro-speak
```

It synthesizes with Kokoro-82M at 24 kHz, writes a temporary WAV, and plays it
through the first working player it finds (`pw-play`, `paplay`, `aplay`,
`ffplay`, then `mpv`). The default voice is `af_heart` at speed 1.0 — the same
default the `explainer` skill uses.

Everything is vendored in this skill directory:

```
<this-skill-directory>/
  flake.nix                 the input a machine adds
  modules/flake-parts.nix   flake-level settings -> flake.nixosModules.kokoro
  modules/system.nix        programs.kokoro-tts (NixOS and system-manager)
  nix/package.nix           model, Python env, kokoro-speak wrapper
  bin/kokoro-speak          the pipe-friendly CLI
  bench/bench.py            warm synthesis timings at several text lengths
  bench/cold.py             fresh-process latency, model load included
  bench/compare.py          two bench JSON files -> a Markdown table
  BENCHMARK.md              measured CPU and CUDA results, methodology
```

## 1. Add the flake input

The skill is a flake. Point a machine at the checkout by path while the skill
is being developed, or at a git URL once it is published:

```nix
# flake.nix, inside inputs
kokoro-speak.url = "path:/home/sshine/.agents/skills/kokoro-speak";
# The module builds with the consuming system's pkgs; following nixpkgs also
# keeps this input's own package output on the same nixpkgs.
kokoro-speak.inputs.nixpkgs.follows = "nixpkgs";
kokoro-speak.inputs.flake-parts.follows = "flake-parts";
```

Then import its flake-parts module once, in a module of the consuming flake:

```nix
# modules/kokoro-speak.nix
{ inputs, ... }:
{
  imports = [ inputs.kokoro-speak.flakeModules.default ];

  # Optional flake-wide defaults. These become the defaults of
  # programs.kokoro-tts on every system that imports the module below.
  # flake.kokoro-tts = {
  #   voice = "af_heart";
  #   speed = 1.0;
  # };
}
```

## 2. Add the system module

Both NixOS and system-manager use the same module system, so the same module
works on both. Add it to the system that should speak:

```nix
# NixOS: modules/nixos-configurations.nix
modules = [
  # ...
  config.flake.nixosModules.kokoro
];

# system-manager: modules/system.nix
modules = [
  # ...
  config.flake.nixosModules.kokoro
];
```

Apply it the way that machine already applies configuration:

```bash
# NixOS
sudo nixos-rebuild switch --flake .

# system-manager
just switch
```

The module installs a `kokoro-speak` wrapper, not the bare package, so the
configured voice and speed are the command's defaults.

## 3. Settings

`flake.kokoro-tts` sets flake-wide defaults; `programs.kokoro-tts` is the
per-system module and can override any of them:

| Option | Default | Meaning |
|---|---|---|
| `enable` | `true` | Install `kokoro-speak` on this system. |
| `cudaSupport` | `false` | Build ONNX Runtime with the CUDA execution provider. |
| `cudaArchitectures` | `"75;80;86;89;120"` | Compute capabilities to compile for; empty uses nixpkgs' full list. |
| `voice` | `"af_heart"` | Kokoro voice. Its first letter also picks the language. |
| `speed` | `1.0` | Speaking rate, 0.5 to 2.0. |
| `lang` | `null` | espeak-ng code; derived from the voice when null. |
| `leadSilence` | `0.0` | Seconds of silence before the first word. |
| `player` | `null` | Player command; auto-detected when null. |

For one host with a different voice, override the system option:

```nix
programs.kokoro-tts = {
  voice = "af_bella";
  speed = 1.1;
};
```

## 4. Use it

```bash
echo "Deployment finished on all three hosts." | kokoro-speak

printf '%s\n' "$long_report" | kokoro-speak --voice af_heart

kokoro-speak --voice bf_emma --speed 1.15 "British English, slightly quicker."

# Synthesize without playing, for inspecting or embedding the audio.
kokoro-speak --out reply.wav --no-play "Saved instead of played."

# Write a WAV to stdout, for another program.
kokoro-speak --out - "Piped as WAV." > reply.wav

# Force one invocation through the CPU even on a CUDA build.
kokoro-speak --device cpu "Short sentence, no GPU setup cost."

# See what the installed onnxruntime can use.
kokoro-speak --list-providers

kokoro-speak --list-voices
```

Flags win over the module defaults. `--voice`, `--speed`, `--lang`, `--device`,
`--lead-silence`, `--player`, `--out`, `--no-play`, `--list-providers` and
`--list-voices` are the whole surface. Text comes from the arguments when
given, otherwise from stdin.

## 5. NVIDIA GPU (optional)

The model is 82M parameters, so a GPU is not required, but CUDA execution makes
long text and batches noticeably faster. Enable it per system:

```nix
programs.kokoro-tts = {
  cudaSupport = true;
  # Optional: drop architectures you do not own to cut nvcc time.
  # 7.5 is RTX 20xx, 8.6 is RTX 30xx, 8.9 is RTX 40xx, 12.0 is RTX 50xx.
  cudaArchitectures = "75;86";
};
```

Or flake-wide, for every system that imports `flake.nixosModules.kokoro`:

```nix
flake.kokoro-tts.cudaSupport = true;
```

The consumer's nixpkgs must allow unfree packages because the CUDA EULA covers
the runtime and cuDNN:

```nix
nixpkgs.config.allowUnfree = true;
```

The first build compiles ONNX Runtime against CUDA, which is much slower than
the CPU build. On a 16-thread i7-11700 with `cudaArchitectures = "86"` it took
about 46 minutes; the default five-architecture list is longer. Later builds
are cached. To build the package without a NixOS configuration:

```bash
nix build .#kokoro-speak-cuda
./result/bin/kokoro-speak --list-providers   # CUDAExecutionProvider must appear
```

The wrapper puts `/run/opengl-driver/lib` on `LD_LIBRARY_PATH` so ONNX Runtime
can find the driver's `libcuda.so`, and names `CUDAExecutionProvider` in
`ONNX_PROVIDER` because kokoro-onnx only auto-selects an accelerated provider
for distributions named `onnxruntime-gpu` (nixpkgs' is plain `onnxruntime`).
`--device cpu` is the escape hatch when the driver is broken or the sentence is
so short that CUDA setup costs more than it saves.

Measured on the machine in `BENCHMARK.md`: warm synthesis is 5.1x faster at 5
words, 7.3-8.7x at 20-100 words, and 10.1x at 300-1000 words, reaching about
32x realtime. A fresh one-sentence command is about parity with the CPU because
the CUDA session setup costs 1.5-2.4 s; a paragraph cold run is already 2.8x
faster.

## 6. Verify the install

Do not stop at "the command exists". Synthesize a short file and check it is a
real 24 kHz WAV before asking the user to listen:

```bash
printf 'Kokoro is installed. This is the default voice.' |
  kokoro-speak --out /tmp/kokoro-check.wav --no-play
ffprobe -v error -show_entries stream=sample_rate,channels,duration \
  -of default=nw=1 /tmp/kokoro-check.wav
kokoro-speak --list-providers
pw-play /tmp/kokoro-check.wav   # or paplay / aplay / ffplay
```

On a CUDA build, `--list-providers` must print `CUDAExecutionProvider`; if it
does not, the wrapper and the onnxruntime that the Python environment imported
disagree. The first invocation loads the 326 MB ONNX model and takes several
seconds. Later invocations in a fresh process load it again; this is a CLI, not
a daemon. That is deliberate for the first version. For GPU setup cost see
`BENCHMARK.md`; the short version is that CUDA wins on paragraphs, not on one
short sentence.

To reproduce the benchmark:

```bash
nix run .#kokoro-bench-cpu  -- --label cpu  --json-out /tmp/cpu.json
nix run .#kokoro-bench-cuda -- --label cuda --json-out /tmp/cuda.json
nix shell nixpkgs#python3 -c python3 bench/compare.py /tmp/cpu.json /tmp/cuda.json
```

## Gotchas

- **The wheel is x86_64-linux only.** `espeakng-loader` ships a manylinux
  x86_64 wheel. The flake's `systems` list says so. This skill therefore runs
  on Intel/AMD Linux, not on an Apple Silicon Mac; an M-series port needs a
  different espeak library package and a CoreML/Metal execution provider.
- **CUDA is a build-time choice.** `cudaSupport = true` builds a CUDA onnxruntime
  and bakes `CUDAExecutionProvider` into the wrapper. There is no fallback to
  the CPU build at runtime if the driver disappears; use `--device cpu` or
  install the CPU package instead.
- **A short sentence can be slower on the GPU.** Every CLI invocation creates a
  new ONNX Runtime session, and CUDA setup is a fixed cost. For one or two
  words, `--device cpu` is often the lower-latency choice; for paragraphs and
  reports, CUDA is several times faster. See `BENCHMARK.md`.
- **The voice selects the language.** `af_heart` is American English because
  of the leading `a`; `bf_emma` is British, `zm_yunyang` is Mandarin. Pass
  `--lang` only when espeak wants a variant other than that mapping.
- **Kokoro clips the start of an utterance.** If the first phoneme is being
  cut off, set `leadSilence = 0.05` or pass `--lead-silence 0.05`.
- **No audio server, no playback.** The wrapper includes PipeWire, ALSA and
  FFmpeg players, but the machine still needs a running sound server and an
  output device. `--out FILE --no-play` proves synthesis without one.
- **`--out -` is WAV, not raw PCM.** It is for piping into another program
  that reads WAV, not for an audio device that expects PCM.
- **A response hook should feed text, not markdown furniture.** Strip code
  fences and tables before piping a final agent message if the result should
  be listenable; this CLI speaks exactly what it receives.

## Next step

The command is the integration point for reading an agent session aloud:
whatever hook runs at the end of a session can pipe the final response into
`kokoro-speak`. The OpenCode hook itself is a separate piece of work; this
skill only guarantees the voice is installed and callable from stdin.
