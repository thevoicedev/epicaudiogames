"""Works out where every spoken line sits in one radio play's mixed audio, with the Mini Games mixer's own layout.

build_maps.py runs this once per game, with RP_GAME_DIR set to the game's folder in all-minigames-sites
(alexa/tools/<game>) and that repo's alexa/tools/radioplay on the path. It imports the mixer (mix.py), lays out
every scene, reprompt and common clip exactly as the mixer did when it rendered them, and writes, as JSON:

  {"scenes":  {slug: {"dur": s, "lines": [{"at": s, "len": s, "who": "NARRATOR", "text": "..."}], "approx": [...]}},
   "prompts": {slug: {"dur": s, "lines": [...]}},
   "common":  {slug: {...}},
   "nodes":   [{"id", "slug", "reprompt"}]}

Nothing in all-minigames-sites is written: the mixer's cache saves are switched off, and a word the mixer would
look up with ElevenLabs speech-to-text (to place a sound effect on it) is only read from the existing cache. A
miss is estimated instead and listed under "approx" (it can only move a sound effect, never a line).

Usage: python rp_timings.py <radioplay dir> <out.json>
"""
import json
import re
import sys
from pathlib import Path

RADIOPLAY = Path(sys.argv[1]).resolve()
OUT_FILE = Path(sys.argv[2])
sys.path.insert(0, str(RADIOPLAY))

import rplib  # noqa: E402  (needs RP_GAME_DIR, set by the caller)

rplib._save_durations = lambda: None          # read the duration cache, never write it

import mix  # noqa: E402

mix.stem_gain = lambda *args, **kwargs: 0.0   # gains don't move anything, and measuring them writes a cache

_approx = []
_word_time = mix.word_time


def cached_words(path, cache_dir):
    """The mixer's word timings for a voice take, from its cache only (no speech-to-text calls)."""
    path = Path(path)
    key = rplib.hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    cache = Path(cache_dir) / f"{path.stem}.{key}.json"
    return json.loads(cache.read_text(encoding="utf-8")) if cache.exists() else None


def word_time(prefix, line_n, word, slug_cue):
    """Where a word starts in a line: the cached timing, or an estimate from its place in the text."""
    take = rplib.VO_DIR / f"{prefix}-{line_n:02d}.wav"
    words = cached_words(take, rplib.OUT / "words")
    if words is not None:
        at = rplib.find_word(word, words)
        if at is not None:
            return at
    text = LINE_TEXT.get((prefix, line_n), "")
    plain = rplib.TAG_RE.sub("", text)
    hit = re.search(rf"\b{re.escape(word)}", plain, re.I)
    frac = hit.start() / max(1, len(plain)) if hit else 0.5
    _approx.append({"line": line_n, "word": word})
    return frac * rplib.duration(take)


mix.word_time = word_time
LINE_TEXT = {}


def clean(text):
    return re.sub(r"\s+", " ", rplib.TAG_RE.sub("", text)).strip()


def lines_of(prefix, cues, bed_from_vo, plate):
    n = 0
    for c in cues:
        if "vo" in c:
            n += 1
            LINE_TEXT[(prefix, n)] = c["text"]
    events = []
    del _approx[:]
    _, total, _ = mix.layout(prefix, cues, bed_from_vo, events=events, plate=plate)
    lines = [{"at": round(start, 3), "len": round(length, 3), "who": cue["vo"], "text": clean(cue["text"])}
             for kind, start, length, cue, *_ in (e for e in events if e[0] == "vo")]
    out = {"dur": round(total, 3), "lines": lines}
    if _approx:
        out["approx"] = list(_approx)
    return out


def main():
    script = rplib.load_json("script.json")
    result = {"scenes": {}, "prompts": {}, "common": {}, "nodes": [], "voices": sorted(script.get("voices", {}))}
    for node in script["nodes"]:
        result["nodes"].append({"id": node["id"], "slug": node["slug"], "reprompt": node.get("reprompt")})
    for kind, slug, prefix, cues, bed, bed_from_vo, plate in mix.jobs(script):
        if kind == "prompts":
            take = rplib.VO_DIR / f"{slug}-reprompt.wav"
            text = next(n["reprompt"] for n in script["nodes"] if n["slug"] == slug)
            length = rplib.duration(take)
            # mix.py's prompt clip: the take after the lead-in, then 0.3 s of silence.
            result["prompts"][slug] = {"dur": round(mix.LEAD_IN + length + 0.3, 3),
                                       "lines": [{"at": mix.LEAD_IN, "len": round(length, 3), "who": "NARRATOR", "text": clean(text)}]}
            continue
        result[kind][slug] = lines_of(prefix, cues, bed_from_vo, plate)
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(f"{rplib.GAME.name}: {len(result['scenes'])} scenes, {len(result['prompts'])} prompts, "
          f"{len(result['common'])} common -> {OUT_FILE}")


main()
