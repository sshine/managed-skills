#!/usr/bin/env python3
"""lib/pace.py — how long narration will take, before synthesizing it.

Kokoro's speaking rate is close to linear in characters, and differs a lot by
voice: af_nicole, which whispers, takes nearly twice as long per character as
am_eric. lib/voice-pace.json holds a line per voice, fitted by `--measure`.

  pace.py estimate <video-dir>     predict every scene, and the total
  pace.py measure [voice ...]      re-fit the table (needs Kokoro; slow)

Accuracy, measured against five real scenes the fit had never seen: within 1%
on the total, within about 5% per scene. Respellings in tts_text are the known
blind spot — "M C P" is five characters but three spoken letter names, so a
scene full of them runs longer than predicted. A Latin word inside Chinese
narration goes the other way: its letters are counted at the hanzi rate, so a
scene carrying a shop name predicts a few percent long.
"""

import argparse
import json
import re
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parent
TABLE = LIB / "voice-pace.json"
DEFAULT_VOICE = "af_heart"

# The characters that carry sound. Punctuation is dropped: it sets pause
# lengths, not speech length, and counting it made the fit worse. `measure`
# and `estimate` must agree here, which is why they share one file.
def chars(text: str) -> int:
    return len(re.sub(r"[^\w\s]", "", text))


def spoken(scene: dict) -> str:
    return (scene.get("tts_text") or scene.get("narration") or "").strip()


def predict(pace: dict, text: str) -> float:
    return pace["seconds_per_char"] * chars(text) + pace["intercept"]


# --------------------------------------------------------------- estimate --
def estimate(video: Path) -> int:
    document = json.loads((video / "script.json").read_text(encoding="utf-8"))
    voice = document.get("meta", {}).get("voice", DEFAULT_VOICE)
    table = json.loads(TABLE.read_text(encoding="utf-8"))
    if voice not in table:
        print(f"no measured pace for voice {voice!r}; run 'pace.py measure'",
              file=sys.stderr)
        return 1
    pace = table[voice]

    print(f"{'scene':20} {'chars':>6} {'estimate':>10}")
    total = 0.0
    long_or_short = []
    for scene in document["scenes"]:
        text = spoken(scene)
        seconds = predict(pace, text)
        total += seconds
        print(f"{scene['id']:20} {chars(text):6} {seconds:9.1f}s")
        if not 10.0 <= seconds <= 30.0:
            long_or_short.append((scene["id"], seconds))
    minutes, seconds = divmod(round(total), 60)
    print(f"{'':20} {'':6} {'':->10}")
    print(f"{voice:20} {'':6} {total:9.1f}s  ({minutes}:{seconds:02d})")

    for sid, length in long_or_short:
        verb = "short" if length < 10 else "long"
        print(f"  {sid} is {verb} at {length:.0f}s; scenes read best at 15-25s",
              file=sys.stderr)
    return 0


# ---------------------------------------------------------------- measure --
# Three passages of the same register, differing only in length. The fit is a
# least-squares line through all three, which beat a two-point fit: two points
# extrapolate the per-character rate about 6% too steep.
ENGLISH = [
    "MXroute hosts your email. Its control panel is a web app, which is fine "
    "for a person and useless to an agent.",

    "The server takes three things: the server your account lives on, your "
    "username, and an API key from the panel. There is deliberately no key "
    "flag, because a command line is readable by every process on the host "
    "and lands in your shell history. It refuses to start unless all three "
    "are set, rather than serving tools that would each fail.",

    "By default it serves eight tools, and every one of them only reads. "
    "Adding the writes flag takes you to eighteen. The deletes flag takes you "
    "to twenty two, and it sits behind its own switch because it is the only "
    "tier that destroys stored mail. Reseller tools bring it to thirty two. A "
    "tool you did not ask for is never registered, so it cannot be called by "
    "name either. That matters more than it sounds: an agent that cannot see "
    "a tool cannot be talked into using it, and the blast radius of a mistake "
    "is bounded by what you handed over rather than by what the server "
    "happens to implement. Start with reads, and widen only when you have a "
    "reason to.",
]

# The same three lengths again, because a fit is only as good as the span it
# covers. chars() keeps one hanzi per character and Chinese writes no spaces,
# so a Mandarin rate comes out three to four times an English one; the two are
# not comparable, which is why each voice carries its own line.
MANDARIN = [
    "你的邮箱托管在服务商那里。它的控制面板是一个网页应用，对人来说够用，对智能体来说"
    "却毫无用处。这个服务器要解决的就是这个问题：它把面板背后的接口整理成一组工具，交"
    "给模型按名字直接调用。这样一来，收信、配置和排错都可以在对话里完成。",

    "服务器启动的时候需要三样东西：你的账号所在的服务器地址、用户名，以及在控制面板里"
    "生成的接口密钥。我们故意没有提供传递密钥的命令行参数，因为命令行上的内容，同一台"
    "机器上的任何进程都看得见，而且还会原样留在你的命令历史里。三样东西只要缺一样，服"
    "务器就直接拒绝启动，而不是先跑起来，再让每一个工具在调用的时候各自失败。这样配置"
    "上的错误在第一秒就暴露出来，而不是等到模型已经开始干活才一个接一个地报错。密钥本"
    "身最好放在环境变量或者密码管理器里，由启动脚本读出来再传给服务器，这样它既不会出"
    "现在代码仓库里，也不会出现在日志里。地址写错或者密钥过期的时候，服务器会把原因直"
    "接写出来，而不是让模型去猜一串看不懂的状态码。这几样东西加起来并不多，配置一次就"
    "可以一直用下去，剩下的事情交给模型，它看到的只是一组现成的工具。",

    "默认情况下，服务器只注册八个工具，而且每一个都只读。它们能列出域名、查看邮箱、读"
    "取转发规则和自动回复的设置，但是不会改动任何东西。加上写入开关以后，工具的数量变"
    "成十八个，这时候模型才可以新建邮箱、修改密码、调整转发。删除开关会把数量推到二十"
    "二个，它之所以单独占一个开关，是因为这是唯一一层会真正销毁已经存在服务器上的邮件"
    "的操作，而邮件一旦删掉，服务商那边通常也救不回来。再加上代理商的工具，总数是三十"
    "二个。没有被打开的工具不会被注册，所以模型连它的名字都看不到，自然也没办法凭名字"
    "去调用它。这一点比听上去更重要：一个看不见的工具，是没有办法被说服去使用的。无论"
    "对话被引导到什么方向，模型能做的事情，上限都由你在启动的时候交出去的那一层决定，"
    "而不是由服务器本身实现了多少功能决定。换句话说，出错的范围是你自己划定的，它不会"
    "因为对话变长、任务变复杂而慢慢扩大。这种做法在日常使用里也更省事：工具少，模型挑"
    "工具的时候更准，返回的内容也更短，读起来不费劲。很多时候一次对话真正用到的只有两"
    "三个工具，把其余的几十个都摆在模型面前，除了让它分心，并没有别的好处。等到某一天"
    "你确实需要改动邮箱，再把写入那一层打开就好了，这中间不需要重新安装，也不需要改动"
    "已有的配置，只是在启动命令上多加一个开关而已。如果你用的是托管在别处的配置文件，"
    "那就改一行，重启一次，前后不超过一分钟。真正需要谨慎的只有删除那一层，建议在确认"
    "过备份之后再打开，并且用完就关掉，不要让它一直留在默认配置里。所以我的建议是从只"
    "读开始，等到确实有需要的时候，再一层一层地放开。",
]

# Kokoro names a voice for its language in the first letter, and the espeak
# codes below are the ones tts.py synthesizes with, so a voice is measured the
# way it will later be spoken. A language becomes measurable by gaining
# passages of its own; voices outside this table are left alone.
FAMILIES = {
    "a": ("en-us", ENGLISH),
    "b": ("en-gb", ENGLISH),
    "z": ("cmn", MANDARIN),
}


def fit(xs: list[int], ys: list[float]) -> tuple[float, float]:
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    spread = sum((x - mean_x) ** 2 for x in xs)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / spread
    return slope, mean_y - slope * mean_x


def measure(out: Path, only: list[str]) -> int:
    import os
    import numpy
    from kokoro_onnx import Kokoro
    from kokoro_onnx.config import EspeakConfig

    model_dir = Path(os.environ["KOKORO_MODEL_DIR"])
    voices_path = model_dir / "voices-v1.0.bin"
    kokoro = Kokoro(
        str(model_dir / "kokoro-v1.0.onnx"), str(voices_path),
        espeak_config=EspeakConfig(
            lib_path=os.environ["ESPEAK_LIBRARY"],
            data_path=os.environ.get("ESPEAK_DATA_PATH"),
        ),
    )
    voices = sorted(n for n in numpy.load(voices_path).files
                    if n[:1] in FAMILIES)
    if only:
        voices = [v for v in voices if v in only or v[:1] in only]
        if not voices:
            print(f"no measurable voice matches {' '.join(only)}",
                  file=sys.stderr)
            return 1

    # Merge into the table rather than replace it, so re-fitting one language
    # leaves the others at the numbers they were measured with.
    table = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {}
    for voice in voices:
        lang, texts = FAMILIES[voice[:1]]
        ys = []
        for text in texts:
            samples, rate = kokoro.create(text, voice=voice, speed=1.0, lang=lang)
            ys.append(len(samples) / rate)
        slope, intercept = fit([chars(text) for text in texts], ys)
        table[voice] = {
            "seconds_per_char": round(slope, 6),
            "intercept": round(intercept, 4),
        }
        print(f"{voice}: {slope:.5f} s/char", flush=True)
    out.write_text(json.dumps(table, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    one = sub.add_parser("estimate")
    one.add_argument("video", type=Path)
    two = sub.add_parser("measure")
    two.add_argument("--out", type=Path, default=TABLE)
    two.add_argument("voices", nargs="*")
    args = parser.parse_args()
    if args.command == "estimate":
        return estimate(args.video)
    return measure(args.out, args.voices)


if __name__ == "__main__":
    raise SystemExit(main())
