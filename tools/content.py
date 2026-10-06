"""The audio of the coded games, made into map steps (docs/MAP_FORMAT.md) for their builders in tools/games/.

- tts(text): one of Alexa's lines in the app's voice (Jessica), with the time of every word;
- clip(path): one of the skill's recorded clips, from the Mini Games CDN, as it is (speech is transcribed);
- bed(path, volume): a recorded clip to play under the rest of a turn (the skill's music beds);
- mix(name, layers): clips overlapping at given times (the skill's nested mixers), pre-mixed into one file.

Each returns a step (a dict) with the clip's path, length and transcript, and leaves the file in content/<game>/.
Everything is cached (tools/cache/), so a rebuild only renders what changed. The ElevenLabs key is
ELEVENLABS_API_KEY, from the environment or all-minigames-sites/alexa/.env; it is never printed.
"""
import base64
import difflib
import hashlib
import json
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from voice_audition import api_key

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "tools" / "cache"
CDN = "https://x9gq2b7lta.com/"
API = "https://api.elevenlabs.io"

# The app's voice for every line Alexa used to say (the user's pick, 6 Oct 2026).
VOICE = {"id": "cgSgspJ2msm6clMCkdW9", "name": "jessica", "model": "eleven_multilingual_v2",
         "settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.15, "use_speaker_boost": True}}
HOST = "HOST"
SPEECH_LUFS = -16.0
ENCODE = ["-ac", "1", "-c:a", "aac", "-b:a", "48k", "-ar", "32000", "-movflags", "+faststart"]
# Jessica's lines are speech alone: 32 kbps at 24 kHz is plenty (music and mixes keep ENCODE).
ENCODE_SPEECH = ["-ac", "1", "-c:a", "aac", "-b:a", "32k", "-ar", "24000", "-movflags", "+faststart"]

_lock = threading.Lock()


def run(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *map(str, args)], check=True)


def duration(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
                        str(path)], capture_output=True, text=True)
    return float(p.stdout.strip())


def loudness(path):
    """Integrated loudness (LUFS) of a file, or None for silence."""
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128", "-f", "null", "-"],
                       capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", p.stderr)
    return float(m[-1]) if m and float(m[-1]) > -70 else None


def clean(text):
    """Speech text as it is read and shown: SSML tags out, spaces tidied."""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text)).strip()


def slug(text, n=6):
    words = re.sub(r"[^a-z0-9 ]+", "", text.lower()).split()
    return "-".join(words[:n]) or "line"


def post(path, body=None, files=None, data=None):
    headers = {"xi-api-key": api_key()}
    if files is None:
        headers["Content-Type"] = "application/json"
        req = urllib.request.Request(API + path, headers=headers, data=json.dumps(body).encode())
    else:
        boundary = "eag" + hashlib.sha1(files[1]).hexdigest()[:16]
        parts = []
        for k, v in (data or {}).items():
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{files[0]}"\r\n'
                     f'Content-Type: audio/mpeg\r\n\r\n'.encode() + files[1] + b"\r\n")
        parts.append(f"--{boundary}--\r\n".encode())
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
        req = urllib.request.Request(API + path, headers=headers, data=b"".join(parts))
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503) or attempt == 3:
                raise RuntimeError(f"ElevenLabs {path}: {e.code} {e.read()[:200]!r}") from None
        time.sleep(4 * (attempt + 1))


def similar(a, b, at_least=0.8):
    """Whether two transcripts are the same words, give or take a few."""
    def norm(t):
        return re.sub(r"[^a-z0-9' ]+", " ", t.lower()).split()
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio() >= at_least


def word_starts(text, alignment):
    """The start time of each word of text (split on spaces), from ElevenLabs' character timings."""
    chars, starts = alignment["characters"], alignment["character_start_times_seconds"]
    out, prev = [], " "
    for c, t in zip(chars, starts):
        if not c.isspace() and prev.isspace():
            out.append(round(t, 3))
        prev = c
    return out if len(out) == len(text.split()) else None


class Content:
    """The content of one game: content/<game>/ and the CDN folder its recorded clips come from."""

    def __init__(self, game, cdn_prefix, voices=None, fixes=None):
        self.game = game
        self.prefix = cdn_prefix                    # "en/audio2/leaning-tower-of-pizza/"
        self.dir = ROOT / "content" / game
        self.voices = voices or {}                  # recorded clip folder -> speaker key, for transcripts
        self.fixes = fixes or {}                    # speech-to-text slips -> what the clip says ("=x": all of it)
        self.used = set()                           # every content path the map plays
        self.differs = []                           # (clip, the code's words, what speech-to-text heard)
        self.planning = None                        # while prepare() looks at what a build needs
        self.pool = ThreadPoolExecutor(max_workers=6)

    def prepare(self, build):
        """Runs build() once only to see the lines and clips it uses, renders and fetches those in parallel, then
        runs it for real and returns what it returns."""
        self.planning = {"tts": set(), "clips": set()}
        build()
        plan, self.planning = self.planning, None
        print(f"{len(plan['tts'])} lines in Jessica's voice and {len(plan['clips'])} recorded clips "
              f"(cached ones are skipped)...")
        self.tts_many(plan["tts"])
        list(self.pool.map(lambda c: self._fetch(*c), sorted(plan["clips"])))
        self.used.clear()
        return build()

    def _fetch(self, rel, heard):
        rel, local = self._cdn(rel)
        if heard:
            self.transcribe(local)

    def _placeholder(self, kind, who=None, text=None):
        lines = [{"at": 0.0, "len": 1.0, "who": who, "text": text}] if text else []
        return {"play": f"{kind}/planning", "dur": 1.0, "lines": lines}

    # ----- Alexa's lines, in the app's voice -----

    def tts_many(self, texts):
        """Renders and encodes many lines at once (in parallel); tts() then finds them ready."""
        list(self.pool.map(self.tts, sorted({clean(t) for t in texts if clean(t)})))

    def _tts_raw(self, text):
        key = hashlib.sha1(json.dumps([VOICE["id"], VOICE["model"], VOICE["settings"], text]).encode()).hexdigest()[:16]
        folder = CACHE / "tts" / VOICE["name"]
        mp3, info = folder / f"{key}.mp3", folder / f"{key}.json"
        if not mp3.exists():
            r = post(f"/v1/text-to-speech/{VOICE['id']}/with-timestamps?output_format=mp3_44100_128",
                     {"text": text, "model_id": VOICE["model"], "voice_settings": VOICE["settings"]})
            folder.mkdir(parents=True, exist_ok=True)
            info.write_text(json.dumps({"text": text, "alignment": r.get("alignment")}), encoding="utf-8")
            mp3.write_bytes(base64.b64decode(r["audio_base64"]))
        return key, mp3, json.loads(info.read_text(encoding="utf-8"))

    def tts(self, text, who=HOST):
        """A line in the app's voice: content/<game>/tts/<slug>.m4a."""
        text = clean(text)
        if self.planning is not None:
            self.planning["tts"].add(text)
            return self._placeholder("tts", who, text)
        key, mp3, info = self._tts_raw(text)
        rel = f"tts/{slug(text)}-{key[:6]}"
        out = self.dir / f"{rel}.m4a"
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            lufs = loudness(mp3)
            gain = (SPEECH_LUFS - lufs) if lufs is not None else 0.0
            run("-i", mp3, "-af", f"volume={gain:.2f}dB,alimiter=limit=0.89:level=false", *ENCODE_SPEECH, out)
        dur = duration(out)
        alignment = info.get("alignment") or {}
        ends = alignment.get("character_end_times_seconds") or [dur]
        line = {"at": 0.0, "len": round(min(dur, max(ends)), 3), "who": who, "text": text}
        w = word_starts(text, alignment) if alignment else None
        if w:
            line["w"] = w
        self.used.add(rel)
        return {"play": rel, "dur": round(dur, 3), "lines": [line]}

    # ----- The skill's recorded clips -----

    def _cdn(self, rel):
        rel = rel.split("?")[0]
        local = CACHE / "cdn" / self.game / rel
        if not local.exists():
            req = urllib.request.Request(CDN + self.prefix + rel, headers={"User-Agent": "epicaudiogames-tools/1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            local.parent.mkdir(parents=True, exist_ok=True)
            local.write_bytes(data)
        return rel, local

    def clip(self, rel, text=None, who=None, sfx=None, check=False):
        """A recorded clip as it is: content/<game>/audio/<rel>. Speech is transcribed unless text is given;
        sfx=True marks music and sound effects (no transcript). With check=True, the given text is shown with the
        times speech-to-text heard, unless it heard other words: then those are shown, and the clip is listed in
        self.differs (a line recorded from other words, or one file shared by two lines)."""
        if self.planning is not None:
            self.planning["clips"].add((rel.split("?")[0], not sfx and (text is None or check)))
            return self._placeholder("audio", who or "VOICE", None if sfx else (text or "planning"))
        rel, local = self._cdn(rel)
        stem = rel.rsplit(".", 1)[0]
        out = self.dir / "audio" / rel
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(local.read_bytes())
        dur = duration(out)
        path = f"audio/{stem}"
        self.used.add(path)
        if sfx:
            return {"play": path, "dur": round(dur, 3), "lines": [], "sfx": True}
        who = who or self.speaker(rel)
        if text is None:
            heard = self.transcribe(local)
            if not heard["text"]:
                return {"play": path, "dur": round(dur, 3), "lines": [], "sfx": True}
            line = {"at": heard["start"], "len": round(max(0.1, heard["end"] - heard["start"]), 3), "who": who,
                    "text": heard["text"]}
            if heard["w"]:
                line["w"] = heard["w"]
        elif check:
            heard = self.transcribe(local)
            shown = clean(text)
            if heard["text"] and not similar(heard["text"], shown):
                self.differs.append((path, shown, heard["text"]))
                shown = heard["text"]
            if heard["text"]:
                line = {"at": heard["start"], "len": round(max(0.1, heard["end"] - heard["start"]), 3), "who": who,
                        "text": shown}
                if len(heard["starts"]) == len(shown.split()):
                    line["w"] = heard["starts"]
            else:
                line = {"at": 0.0, "len": round(dur, 3), "who": who, "text": shown}
        else:
            line = {"at": 0.0, "len": round(dur, 3), "who": who, "text": clean(text)}
        return {"play": path, "dur": round(dur, 3), "lines": [line]}

    def speaker(self, rel):
        for folder, who in self.voices.items():
            if rel.startswith(folder):
                return who
        return "VOICE"

    def transcribe(self, local):
        """What a recorded clip says (ElevenLabs speech-to-text, cached by the file's content)."""
        data = local.read_bytes()
        key = hashlib.sha1(data).hexdigest()[:16]
        cache = CACHE / "stt" / f"{key}.json"
        if not cache.exists():
            r = post("/v1/speech-to-text", files=(local.name, data),
                     data={"model_id": "scribe_v1", "language_code": "en", "tag_audio_events": "false",
                           "timestamps_granularity": "word"})
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(r), encoding="utf-8")
        r = json.loads(cache.read_text(encoding="utf-8"))
        words = [w for w in r.get("words", []) if w.get("type") == "word"]
        if not words:
            return {"text": "", "start": 0.0, "end": 0.0, "w": None, "starts": []}
        text = clean(r.get("text") or " ".join(w["text"] for w in words))
        for wrong, right in self.fixes.items():
            if wrong.startswith("="):           # "=Father": only when that is all it heard
                text = right if text == wrong[1:] else text
            else:
                text = text.replace(wrong, right)
        start = round(words[0]["start"], 3)
        starts = [round(x["start"] - start, 3) for x in words]
        w = starts if len(words) == len(text.split()) else None
        return {"text": text, "start": start, "end": words[-1]["end"], "w": w, "starts": starts}

    def bed(self, rel, volume):
        """A recorded clip under the rest of the turn, at this volume (0 to 1)."""
        step = self.clip(rel, sfx=True)
        return {"bed": step["play"], "volume": volume, "dur": step["dur"]}

    def bed_of(self, step, volume):
        """A clip made here (a mix) under the rest of the turn."""
        return {"bed": step["play"], "volume": volume, "dur": step["dur"]}

    # ----- Overlapping clips, pre-mixed -----

    def mix(self, name, layers):
        """Clips that overlap, as one file: content/<game>/mix/<name>-<hash>.m4a.

        layers: [{"step": a play step, "at": seconds, "volume": 1.0, "fade_in": seconds, "trim": False}]. A layer
        with "trim" (the skill's trimToParent) is cut where the longest other layer ends.
        """
        if self.planning is not None:
            return self._placeholder("mix")
        spec = [{"play": l["step"]["play"], "at": round(l.get("at", 0.0), 3), "volume": l.get("volume", 1.0),
                 "fade_in": l.get("fade_in", 0.0), "trim": bool(l.get("trim"))} for l in layers]
        key = hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:8]
        rel = f"mix/{name}-{key}"
        out = self.dir / f"{rel}.m4a"
        ends = [l.get("at", 0.0) + l["step"]["dur"] for l, s in zip(layers, spec) if not s["trim"]]
        total = max(ends) if ends else max(l.get("at", 0.0) + l["step"]["dur"] for l in layers)
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            args, chains = [], []
            for i, s in enumerate(spec):
                src = next(p for p in self.dir.glob(f"{s['play']}.*"))
                args += ["-i", src]
                fade = f"afade=t=in:d={s['fade_in']}," if s["fade_in"] else ""
                chains.append(f"[{i}]aresample=44100,aformat=channel_layouts=mono,{fade}volume={s['volume']},"
                              f"adelay={int(s['at'] * 1000)}:all=1,apad=whole_dur={total:.3f}[l{i}]")
            chains.append(f"{''.join(f'[l{i}]' for i in range(len(spec)))}amix=inputs={len(spec)}:normalize=0:"
                          f"duration=longest,atrim=0:{total:.3f},alimiter=limit=0.89:level=false[m]")
            run(*args, "-filter_complex", ";".join(chains), "-map", "[m]", *ENCODE, out)
        lines = []
        for l in layers:
            for ln in l["step"].get("lines", []):
                lines.append(dict(ln, at=round(ln["at"] + l.get("at", 0.0), 3)))
        lines.sort(key=lambda x: x["at"])
        self.used.add(rel)
        step = {"play": rel, "dur": round(duration(out), 3), "lines": lines}
        if not lines:
            step["sfx"] = True
        return step

    def size_report(self):
        files = [p for p in self.dir.rglob("*") if p.is_file() and str(p.relative_to(self.dir).with_suffix("")).replace("\\", "/") in self.used]
        return len(files), sum(p.stat().st_size for p in files)
