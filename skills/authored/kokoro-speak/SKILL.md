---
name: kokoro-speak
description: >-
  Install Kokoro-82M as an offline text-to-speech command on a NixOS or
  numtide/system-manager machine. The skill vendors the model, the Python
  wheels nixpkgs lacks, an espeak-ng and audio-player wrapper, and a
  flake-parts module whose settings become NixOS/system-manager options, so
  text piped on stdin is spoken locally with no cloud and no API key. Use when
  asked to make a computer talk, add local TTS, install Kokoro, read text or an
  agent's final response aloud, or package a speech command for a Nix system.
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

kokoro-speak --list-voices
```

Flags win over the module defaults. `--voice`, `--speed`, `--lang`,
`--lead-silence`, `--player`, `--out`, `--no-play` and `--list-voices` are the
whole surface. Text comes from the arguments when given, otherwise from stdin.

## 5. Verify the install

Do not stop at "the command exists". Synthesize a short file and check it is a
real 24 kHz WAV before asking the user to listen:

```bash
printf 'Kokoro is installed. This is the default voice.' |
  kokoro-speak --out /tmp/kokoro-check.wav --no-play
ffprobe -v error -show_entries stream=sample_rate,channels,duration \
  -of default=nw=1 /tmp/kokoro-check.wav
pw-play /tmp/kokoro-check.wav   # or paplay / aplay / ffplay
```

The first invocation loads the 326 MB ONNX model and takes several seconds.
Later invocations in a fresh process load it again; this is a CLI, not a
daemon. That is deliberate for the first version.

## Gotchas

- **The wheel is x86_64-linux only.** `espeakng-loader` ships a manylinux
  x86_64 wheel. The flake's `systems` list says so.
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
