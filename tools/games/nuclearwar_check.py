"""Checks Don's clips for Nuclear War: speech-to-text on each, compared with the line it should say.

ElevenLabs sometimes drops or doubles a word, or reads a name oddly; short pieces of sentences are the likeliest.
This lists every clip whose words don't match (numbers compared as numbers: "twelve" is 12), for a listen and, if
need be, a new take (delete its file in tools/cache/tts/don/ and build again).

Usage (from the repo root, after tools/games/nuclearwar.py): python tools/games/nuclearwar_check.py [--all]
"""
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import DON, ROOT, Content  # noqa: E402

GAME = "nuclear-war"
CLIPS = json.loads((ROOT / "games" / GAME / "clips.json").read_text(encoding="utf-8"))
LINES = {l["text"]: l for l in json.loads((ROOT / "games" / GAME / "lines.json").read_text(encoding="utf-8"))}
c = Content(GAME, "en/audio2/", voice=DON)

ONES = {"zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}


# What speech-to-text hears for words Don says right: the same word, spelt its way.
SAME = {"lion": "lyon", "lions": "lyons", "marcel": "marseille", "cremone": "cremonne", "cremon": "cremonne",
        "putin": "poo tin", "pootin": "poo tin", "hu": "hoo", "hooflung": "hoo flung", "forth": "fourth",
        "whoops": "woops", "anymore": "any more", "forcefield": "force field", "forcefields": "force fields",
        "kame": "came", "joined": "joint", "fengdong": "flung dung", "our": "are"}


def words(text):
    """Lower-case words, with spelled numbers made digits ("one hundred and twelve" -> "112", "1st" -> "first")."""
    text = text.lower().replace("%", " percent").replace(",", "").replace("-", " ").replace("saint ", "st ")
    text = text.replace("500k", "500 thousand").replace("750k", "750 thousand")
    text = re.sub(r"\ba hundred\b", "one hundred", text)
    text = re.sub(r"\bat a (\d)", r"at \1", text)
    text = " ".join(SAME.get(t, t) for t in re.findall(r"[a-z0-9']+(?:\.[0-9]+)?", text))
    toks = re.findall(r"[a-z']+|\d+(?:\.\d+)?", text)
    out, num = [], None

    def flush():
        nonlocal num
        if num is not None:
            out.append(str(num[0] + num[1]))
            num = None

    for t in toks:
        if t in ONES or t in TENS or t in ("hundred", "thousand") or re.fullmatch(r"\d+", t):
            total, cur = num or (0, 0)
            if t == "hundred":
                cur = (cur or 1) * 100
            elif t == "thousand":
                total, cur = total + (cur or 1) * 1000, 0
            else:
                cur += ONES.get(t, TENS.get(t, int(t) if t.isdigit() else 0))
            num = (total, cur)
        elif t == "and" and num is not None:
            continue
        else:
            flush()
            out.append(t)
    flush()
    # "twelve point four" -> "12.4"
    for i in range(len(out) - 2, 0, -1):
        if out[i] == "point" and out[i - 1].isdigit() and out[i + 1].isdigit():
            out[i - 1:i + 2] = [f"{out[i - 1]}.{out[i + 1]}"]
    return out


def check(item):
    text, step = item
    local = next((ROOT / "content" / GAME).glob(f"{step['play']}.*"))
    heard = c.transcribe(local)["text"]
    want = words(LINES.get(text, {}).get("speak", text))
    got = words(heard)
    return text, heard, want == got or " ".join(want) == " ".join(got)


def main():
    voice = CLIPS["voice"]
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(check, sorted(voice.items())))
    bad = [(t, h) for t, h, ok in results if not ok]
    for t, h in bad:
        print(f"{t!r}\n    heard {h!r}")
    print(f"{len(results) - len(bad)} of {len(results)} clips say their words; {len(bad)} to listen to")


if __name__ == "__main__":
    main()
