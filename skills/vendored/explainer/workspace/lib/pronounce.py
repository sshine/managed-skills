#!/usr/bin/env python3
"""lib/pronounce.py — what the voice will actually say, before synthesizing it.

Kokoro phonemizes through espeak-ng, so espeak's output is not a guess about
the narration: it is the narration. This asks it, so a respelling is a reply to
something heard rather than a precaution.

Two reports:

  tokens to check   Words this cannot vouch for, with espeak's reading. Most
                    will be right; the point is to look, not to rewrite.
  respellings       Every tts_text override, as-written against respelled. A
                    respelling that changes no phoneme is dead weight, and one
                    that changes the wrong phoneme is a regression that no
                    amount of rereading the manuscript will show.

Then Kokoro reads the flagged words aloud in the manuscript's own voice, since
IPA settles what the phonemes are and not whether they are the right ones.

Advisory throughout: it exits 0 whatever it finds, and non-zero only when it
cannot run. Which readings are wrong is a judgement about the subject, not
something a lexicon settles.

  pronounce.py <video-dir> [--no-audio]
"""

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import cmudict

VOICE = "en-us"
PREAMBLE = "You may validate the pronunciation of the following words."

# Keep dots, digits and internal punctuation: charts.toml and oauth2-proxy are
# one token each, and that is exactly what makes them worth reading aloud.
TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9.\-_/]*[A-Za-z0-9]|[A-Za-z]")

# CMUdict holds lemmas. espeak derives regular endings from the stem, so a
# known stem is a known pronunciation and the inflection is not news.
SUFFIXES = ("'s", "es", "ed", "ing", "ly", "ers", "er", "s", "d")
PREFIXES = ("un", "re", "pre", "non", "mis", "over", "under")

VOWELS = set("AEIOUY")


def espeak(text: str) -> str:
    """espeak's IPA for one token or phrase, or "" if espeak is unavailable."""
    try:
        done = subprocess.run(
            ["espeak-ng", "-v", VOICE, "-q", "--ipa", "--", text],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return " ".join(done.stdout.split())


def segments(text: str) -> str:
    """IPA with spacing and stress dropped: the sounds, not their emphasis."""
    return re.sub(r"[\sˈˌ]", "", espeak(text))


def compare(before: str, after: str) -> tuple[str, bool]:
    """How a respelling differs from the text it replaces, and whether it pays.

    A respelling only pays for itself by changing a sound. Moving the stress
    around a spelled-out acronym is the common way to spend one for nothing,
    and it is invisible in a diff of the manuscript.
    """
    if espeak(before) == espeak(after):
        return "NO CHANGE", False
    if segments(before) == segments(after):
        return "only the stress moves", False
    return "changes the reading", True


class Lexicon:
    def __init__(self) -> None:
        self.words = set(cmudict.dict().keys())

    def holds(self, word: str) -> bool:
        word = word.lower()
        if word in self.words:
            return True
        if any(
            word[: -len(s)] in self.words
            for s in SUFFIXES
            if len(word) > len(s) + 2 and word.endswith(s)
        ):
            return True
        return any(
            word[len(p) :] in self.words
            for p in PREFIXES
            if len(word) > len(p) + 2 and word.startswith(p)
        )

    def knows(self, token: str) -> bool:
        """Known if the token is a word, or is built from words."""
        word = token.lower().strip(".")
        if self.holds(word):
            return True
        parts = [p for p in re.split(r"[-_]", word) if p]
        if len(parts) > 1 and all(self.knows(p) for p in parts):
            return True
        # A closed compound — hostname, lockfile, allowlist — reads correctly
        # from its parts, so splitting it keeps those out of the report.
        return any(
            self.holds(word[:i]) and self.holds(word[i:])
            for i in range(len(word) - 2, 2, -1)
        )


def classify(token: str) -> str:
    core = token.strip(".")
    if "." in core or "/" in core:
        return "dotted"
    if re.search(r"[A-Za-z]\d|\d[A-Za-z]", core):
        return "alphanumeric"
    if core.isupper() and len(core) > 1:
        return "allcaps"
    if re.search(r"[a-z][A-Z]", core) or (core[:1].isupper() and core[1:2].isupper()):
        return "camelcase"
    return "word"


def worth_checking(token: str, kind: str, lexicon: Lexicon) -> bool:
    if kind == "word":
        return not lexicon.knows(token)
    if kind == "allcaps":
        # A letter sequence with no vowel cannot be read as a word, and espeak
        # spells every one of them out correctly. The vowel-bearing ones are
        # the coin toss: YAML and NASA come out right, OIDC comes out "oydk".
        return bool(VOWELS & set(token.strip(".")))
    return True


def report_tokens(scenes: list[dict], lexicon: Lexicon) -> list[str]:
    # The reader-facing narration is the input: tts_text is the answer to this
    # report, so reading it back would only confirm the author's own guess.
    flagged: dict[str, tuple[str, str]] = {}
    for scene in scenes:
        for token in TOKEN.findall(scene.get("narration", "")):
            if token in flagged or token.lower() in {"a", "i"}:
                continue
            kind = classify(token)
            if worth_checking(token, kind, lexicon):
                flagged[token] = (kind, scene["id"])

    print(f"{'token':24} {'class':14} {'first seen':16} espeak says")
    print("-" * 96)
    spoken: dict[str, str] = {}
    for token, (kind, scene_id) in sorted(
        flagged.items(), key=lambda kv: (kv[1][0], kv[0].lower())
    ):
        print(f"{token:24} {kind:14} {scene_id:16} {espeak(token)}")
        # loki and Loki are one word to the ear; say it once.
        spoken.setdefault(segments(token), token)
    print(f"\n{len(flagged)} tokens to check")
    return list(spoken.values())


def respellings(scene: dict) -> list[tuple[str, str]]:
    """The word runs tts_text replaces, paired with their replacements."""
    narration = scene.get("narration", "")
    spoken = scene.get("tts_text")
    if not spoken or spoken == narration:
        return []
    before, after = narration.split(), spoken.split()
    return [
        (" ".join(before[i1:i2]), " ".join(after[j1:j2]))
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(
            None, before, after
        ).get_opcodes()
        if op != "equal" and before[i1:i2] and after[j1:j2]
    ]


def report_respellings(scenes: list[dict]) -> None:
    pairs = [(s["id"], *p) for s in scenes for p in respellings(s)]
    if not pairs:
        return

    print(f"\n{'scene':16} {'as written':24} {'respelled as':24} effect")
    print("-" * 96)
    idle = 0
    for scene_id, before, after in pairs:
        effect, earns_it = compare(before, after)
        idle += not earns_it
        print(f"{scene_id:16} {before:24} {after:24} {effect}")
        if earns_it:
            print(f"{'':16}   as written  {espeak(before)}")
            print(f"{'':16}   respelled   {espeak(after)}")

    print(f"\n{len(pairs)} respellings, {idle} changing no sound")


def synthesize(text: str, voice: str, wav: Path) -> bool:
    model_dir = Path(os.environ.get("KOKORO_MODEL_DIR", ""))
    lib = os.environ.get("ESPEAK_LIBRARY", "")
    if not model_dir.is_dir() or not os.path.exists(lib):
        print("no Kokoro on the environment — skipping playback", file=sys.stderr)
        return False

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
    samples, rate = kokoro.create(text, voice=voice, lang="en-us")
    soundfile.write(wav, samples, rate)
    return True


def recite(tokens: list[str], voice: str, out: Path) -> None:
    """Read the flagged words aloud in the voice the video will use.

    Each word is its own sentence. The full stop is doing real work: Kokoro
    gives it a longer gap than a comma, which is what makes a list of bare
    nouns audible as separate words rather than one run-on phrase.

    The clip is cached beside the scene audio and keyed by what it says, so
    rerunning after an unrelated edit replays rather than re-synthesizes. The
    word list is derived from the manuscript, so a key that still matches means
    there is nothing new to hear.
    """
    text = f"{PREAMBLE} {'. '.join(tokens)}."
    key = f"{voice}\n{text}\n"
    out.mkdir(parents=True, exist_ok=True)
    wav, key_path = out / "pronounce.wav", out / "pronounce.key"

    cached = (
        wav.exists()
        and key_path.exists()
        and key_path.read_text(encoding="utf-8") == key
    )
    print(f"\nreciting in {voice}{' (cached)' if cached else ''}: {', '.join(tokens)}")
    if not cached:
        if not synthesize(text, voice, wav):
            return
        key_path.write_text(key, encoding="utf-8")

    try:
        subprocess.run(["ffplay", "-v", "error", "-nodisp", "-autoexit", str(wav)])
    except OSError:
        print("ffplay not on PATH — skipping playback", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument(
        "--no-audio", action="store_true", help="report only, do not play anything"
    )
    args = parser.parse_args()

    script = args.video / "script.json"
    if not script.is_file():
        print(f"no script.json in {args.video}", file=sys.stderr)
        return 1
    if not espeak("test"):
        print("espeak-ng not on PATH — enter 'nix develop'", file=sys.stderr)
        return 1

    document = json.loads(script.read_text(encoding="utf-8"))
    scenes = document["scenes"]
    tokens = report_tokens(scenes, Lexicon())
    report_respellings(scenes)
    if tokens and not args.no_audio:
        voice = document.get("meta", {}).get("voice", "af_heart")
        recite(tokens, voice, args.video / "out")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
