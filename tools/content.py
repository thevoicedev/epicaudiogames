"""The audio of the coded games, made into map steps (docs/MAP_FORMAT.md) for their builders in tools/games/.

- tts(text): one of Alexa's lines in the app's voice (Jessica, or a game's own: Nuclear War has Don), with the time
  of every word;
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
import urllib.parse
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
# Nuclear War's announcer instead (the user's pick, 6 Oct 2026): "Don - Movie Trailer Narrator", ElevenLabs library.
DON = {"id": "JJCR1UICgHnHljtvu5uF", "name": "don", "model": "eleven_multilingual_v2",
       "settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.15, "use_speaker_boost": True}}
HOST = "HOST"
SPEECH_LUFS = -16.0
ENCODE = ["-ac", "1", "-c:a", "aac", "-b:a", "48k", "-ar", "32000", "-movflags", "+faststart"]
# Jessica's lines are speech alone: 32 kbps at 24 kHz is plenty (music and mixes keep ENCODE).
ENCODE_SPEECH = ["-ac", "1", "-c:a", "aac", "-b:a", "32k", "-ar", "24000", "-movflags", "+faststart"]
# Or Ogg Opus, smaller for the same sound, and with much less overhead per file (Nuclear War's thousands of lines).
ENCODE_OPUS = ["-ac", "1", "-c:a", "libopus", "-b:a", "24k", "-application", "audio", "-ar", "48000"]

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


def post(path, body=None, files=None, data=None, raw=False):
    """An ElevenLabs request: its JSON answer, or with raw, its bytes (the sound effect and music endpoints answer
    with the audio itself)."""
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
                return r.read() if raw else json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503) or attempt == 3:
                raise RuntimeError(f"ElevenLabs {path}: {e.code} {e.read()[:200]!r}") from None
        time.sleep(4 * (attempt + 1))


def samples(path, rate=16000):
    """A file's sound as mono 16-bit samples."""
    import array
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "s16le", "-ac", "1", "-ar", str(rate), "-"],
                         capture_output=True, check=True).stdout
    return array.array("h", raw)


def quietest(pcm, lo, hi, rate=16000):
    """The middle of the quietest 10 ms between lo and hi seconds: where to cut between two words."""
    win, hop = int(rate * 0.010), int(rate * 0.005)
    best, at = None, (lo + hi) / 2
    i, end = max(0, int(lo * rate)), min(len(pcm), int(hi * rate))
    while i + win <= end:
        e = sum(x * x for x in pcm[i:i + win])
        if best is None or e < best:
            best, at = e, (i + win / 2) / rate
        i += hop
    return at


def last_sound(pcm, lo, hi, rate=16000):
    """Where the last sound between lo and hi seconds ends: the end of the last 10 ms within 35 dB of the loudest
    (quieter is the room's hiss). A scrap shorter than 0.1 s after a pause of 0.2 s or more is passed over: a breath,
    or the start of the next words, which ElevenLabs sometimes goes on to when it's given them as context. None if
    there's nothing."""
    win = int(rate * 0.010)
    i0, i1 = max(0, int(lo * rate)), min(len(pcm), int(hi * rate))
    power = [sum(x * x for x in pcm[i:i + win]) / win for i in range(i0, i1 - win + 1, win)]
    if not power or max(power) <= 0:
        return None
    floor = max(power) * 10 ** (-35 / 10)
    loud = [k for k, p in enumerate(power) if p > floor]
    k = len(loud) - 1
    while k > 0 and loud[k] - loud[k - 1] < 20:         # back to the start of the last run of sound
        k -= 1
    last = loud[k - 1] if k > 0 and loud[-1] - loud[k] < 10 else loud[-1]
    return (i0 + (last + 1) * win) / rate


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


def tts_context(context):
    """The text around a line that ElevenLabs takes into account for its flow (previous_text, next_text: the
    paragraphs before and after it, for the app's spoken help), without the empty ones; {} for none."""
    context = context or {}
    return {k: clean(context[k]) for k in ("previous_text", "next_text") if context.get(k) and clean(context[k])}


def tts_key(voice, text, context=None):
    """A line's cache key (tools/cache/tts/<voice>/<key>.mp3). Without context it is what it has always been, so no
    line already rendered is paid for again; the context, when there is one, is part of it."""
    parts = [voice["id"], voice["model"], voice["settings"], text]
    context = tts_context(context)
    if context:
        parts.append(context)
    return hashlib.sha1(json.dumps(parts).encode()).hexdigest()[:16]


class Content:
    """The content of one game: content/<game>/ and the CDN folder its recorded clips come from."""

    def __init__(self, game, cdn_prefix, voices=None, fixes=None, out=None, voice=VOICE, trim=False, opus=False,
                 tail=None):
        self.game = game
        self.voice = voice                          # who reads Alexa's lines
        self.trim = trim                            # cut the silence around them (lines said in pieces)
        # With trim, the silence after a whole line's last sound cut to this many seconds (the app's spoken help:
        # ElevenLabs times its last character to the end of its audio, however much silence that is). None: kept.
        self.tail = tail
        self.speech = (".opus", ENCODE_OPUS) if opus else (".m4a", ENCODE_SPEECH)     # how they're encoded
        self.prefix = cdn_prefix                    # "en/audio2/leaning-tower-of-pizza/"
        self.dir = Path(out) if out else ROOT / "content" / game     # a pack build writes elsewhere
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
        print(f"{len(plan['tts'])} lines in {self.voice['name'].title()}'s voice and {len(plan['clips'])} recorded "
              f"clips (cached ones are skipped)...")
        self.tts_many(plan["tts"])
        list(self.pool.map(lambda c: self._fetch(*c), sorted(plan["clips"], key=str)))
        self.used.clear()
        return build()

    def _fetch(self, rel, heard, turns=False):
        rel, local = self._cdn(rel)
        if heard:
            self.transcribe(local, diarize=turns)

    def _placeholder(self, kind, who=None, text=None):
        lines = [{"at": 0.0, "len": 1.0, "who": who, "text": text}] if text else []
        return {"play": f"{kind}/planning", "dur": 1.0, "lines": lines}

    # ----- Alexa's lines, in the app's voice -----

    def tts_many(self, texts):
        """Renders and encodes many lines at once (in parallel); tts() then finds them ready. A line is a text, or
        the arguments of tts() as a tuple (text, speak, before, after, piece), then its context's items if it has
        one."""
        lines = {(t if isinstance(t, tuple) else (clean(t), None, "", "", False)) for t in texts}
        list(self.pool.map(lambda a: self.tts(*a[:5], context=dict(a[5:]) or None),
                           sorted((l for l in lines if l[0]), key=str)))

    def _tts_raw(self, text, context=None):
        v = self.voice
        context = tts_context(context)
        key = tts_key(v, text, context)
        folder = CACHE / "tts" / v["name"]
        mp3, info = folder / f"{key}.mp3", folder / f"{key}.json"
        if not mp3.exists():
            r = post(f"/v1/text-to-speech/{v['id']}/with-timestamps?output_format=mp3_44100_128",
                     {"text": text, "model_id": v["model"], "voice_settings": v["settings"], **context})
            folder.mkdir(parents=True, exist_ok=True)
            info.write_text(json.dumps({"text": text, "alignment": r.get("alignment"),
                                        **({"context": context} if context else {})}), encoding="utf-8")
            mp3.write_bytes(base64.b64decode(r["audio_base64"]))
        return key, mp3, json.loads(info.read_text(encoding="utf-8"))

    def tts(self, text, speak=None, before="", after="", piece=False, who=HOST, context=None):
        """A line in the game's voice: content/<game>/tts/<slug>.m4a (or .opus). speak: what's read, when it differs
        from the text shown ("one hundred nine" for "109", "Saint Petersburg" for "St Petersburg"). context: the
        text around it ({"previous_text", "next_text"}: the paragraphs either side, for the app's spoken help), so
        that it's read as part of what's around it; it's in the cache key only when there is one.

        A piece of a sentence (before/after: the words around it) is rendered inside that whole sentence and cut
        out of it between words: at the quietest moment between the middle of the gap the character times give and
        the edge of the piece's own word (the times can be 50 ms out, but never so far that the cut should go into
        the word next to it), with a short fade. It's said as part of a sentence, and nothing of the words around it is left. With trim, a line's silence is cut too: from the
        start, and from the end down to 0.35 s (0.08 s for a piece that the rest of its sentence follows); with tail
        too, the end is cut by what's heard, that long after the last sound."""
        text = clean(text)
        speak = clean(speak) if speak else text
        if self.planning is not None:
            self.planning["tts"].add((text, speak if speak != text else None, before, after, piece)
                                     + tuple(tts_context(context).items()))
            return self._placeholder("tts", who, text)
        full = " ".join(x for x in (before, speak, after) if x)
        key, mp3, info = self._tts_raw(full, context)
        alignment = info.get("alignment") or {}
        starts = alignment.get("character_start_times_seconds") or []
        ends = alignment.get("character_end_times_seconds") or []
        chars = alignment.get("characters") or []
        i0 = len(before) + 1 if before else 0
        i1 = i0 + len(speak)
        timed = len(chars) == len(full) and len(starts) == len(full)
        if (before or after) and not timed:
            raise RuntimeError(f"no character times for {full!r}: can't cut {speak!r} out of it")

        def sound(i, step):
            """The nearest character at or from i (forwards or backwards) that isn't a space."""
            while 0 <= i < len(full) and full[i].isspace():
                i += step
            return i

        fade_in = fade_out = False
        if not self.trim or not timed:
            cut_in, cut_out = 0.0, None
        else:
            pcm = samples(mp3) if before or after else None
            if before:
                gap_from, gap_to = ends[sound(i0 - 1, -1)], starts[sound(i0, 1)]
                cut_in = quietest(pcm, min(gap_to - 0.01, (gap_from + gap_to) / 2), gap_to + 0.01)
                fade_in = True
            else:
                cut_in = max(0.0, starts[sound(0, 1)] - 0.04)
            last = sound(i1 - 1, -1)
            if after:
                gap_from, gap_to = ends[last], starts[sound(i1, 1)]
                cut_out = quietest(pcm, gap_from + 0.01, max(gap_from + 0.02, (gap_from + gap_to) / 2))
                fade_out = True
            else:
                cut_out = ends[last] + (0.08 if piece and not speak.endswith((".", "!", "?")) else 0.35)
                if self.tail is not None and not piece:
                    heard = last_sound(pcm or samples(mp3), cut_in, cut_out)
                    if heard is not None and heard + self.tail < cut_out:
                        cut_out, fade_out = heard + self.tail, True
        # (pieces are named apart: "k", cut at the quiet point)
        rel = f"tts/{slug(text)}-{key[:6]}" + ("k" if self.trim and timed and (before or after) else "")
        ext, encode = self.speech
        out = self.dir / f"{rel}{ext}"
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            lufs = loudness(mp3)
            gain = (SPEECH_LUFS - lufs) if lufs is not None else 0.0
            chain = ""
            if self.trim and timed:
                length = (cut_out - cut_in) if cut_out else None
                chain = f"atrim=start={cut_in:.3f}" + (f":end={cut_out:.3f}" if cut_out else "") + ",asetpts=PTS-STARTPTS,"
                if fade_in:
                    chain += "afade=t=in:d=0.008,"
                if fade_out and length:
                    chain += f"afade=t=out:st={max(0.0, length - 0.012):.3f}:d=0.012,"
            run("-i", mp3, "-af", f"{chain}volume={gain:.2f}dB,alimiter=limit=0.89:level=false", *encode, out)
        dur = duration(out)
        if timed and ends:
            said = ends[sound(i1 - 1, -1)] - cut_in
        else:
            said = max(ends) - cut_in if ends else dur
        line = {"at": 0.0, "len": round(min(dur, said), 3), "who": who, "text": text}
        if timed:
            w, prev = [], " "
            for i in range(i0, i1):
                if not full[i].isspace() and prev.isspace():
                    w.append(round(max(0.0, starts[i] - cut_in), 3))
                prev = full[i]
            if len(w) == len(text.split()):
                line["w"] = w
        self.used.add(rel)
        return {"play": rel, "dur": round(dur, 3), "lines": [line]}

    # ----- The skill's recorded clips -----

    def _cdn(self, rel):
        rel = rel.split("?")[0]
        local = CACHE / "cdn" / self.game / rel
        if not local.exists():
            url = CDN + self.prefix + (urllib.parse.quote(rel) if " " in rel else rel)
            req = urllib.request.Request(url, headers={"User-Agent": "epicaudiogames-tools/1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            local.parent.mkdir(parents=True, exist_ok=True)
            local.write_bytes(data)
        return rel, local

    def clip(self, rel, text=None, who=None, sfx=None, check=False, turns=False):
        """A recorded clip as it is: content/<game>/audio/<rel>. Speech is transcribed unless text is given;
        sfx=True marks music and sound effects (no transcript). With check=True, the given text is shown with the
        times speech-to-text heard, unless it heard other words: then those are shown, and the clip is listed in
        self.differs (a line recorded from other words, or one file shared by two lines). With turns=True (a scene
        with several voices), the transcript is a line per speaker turn."""
        if self.planning is not None:
            self.planning["clips"].add((rel.split("?")[0], not sfx and (text is None or check), turns))
            return self._placeholder("audio", who or "VOICE", None if sfx else (text or "planning"))
        rel, local = self._cdn(rel)
        stem = rel.rsplit(".", 1)[0].replace(" ", "_")      # no spaces in the app's file names
        out = self.dir / "audio" / rel.replace(" ", "_")
        if not out.exists():
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(local.read_bytes())
        dur = duration(out)
        path = f"audio/{stem}"
        self.used.add(path)
        if sfx:
            return {"play": path, "dur": round(dur, 3), "lines": [], "sfx": True}
        who = who or self.speaker(rel)
        if text is None and turns:
            heard = self.transcribe(local, diarize=True)
            if not heard["turns"]:
                return {"play": path, "dur": round(dur, 3), "lines": [], "sfx": True}
            lines = []
            for t in heard["turns"]:
                line = {"at": t["start"], "len": round(max(0.1, t["end"] - t["start"]), 3), "who": who, "text": t["text"]}
                if t["w"]:
                    line["w"] = t["w"]
                lines.append(line)
            return {"play": path, "dur": round(dur, 3), "lines": lines}
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

    def transcribe(self, local, diarize=False):
        """What a recorded clip says (ElevenLabs speech-to-text, cached by the file's content). With diarize, also
        its speaker turns: [{"start", "end", "text", "w"}], split where the voice changes."""
        data = local.read_bytes()
        key = hashlib.sha1(data).hexdigest()[:16] + ("-turns" if diarize else "")
        cache = CACHE / "stt" / f"{key}.json"
        if not cache.exists():
            fields = {"model_id": "scribe_v1", "language_code": "en", "tag_audio_events": "false",
                      "timestamps_granularity": "word"}
            if diarize:
                fields["diarize"] = "true"
            r = post("/v1/speech-to-text", files=(local.name, data), data=fields)
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(r), encoding="utf-8")
        r = json.loads(cache.read_text(encoding="utf-8"))
        words = [w for w in r.get("words", []) if w.get("type") == "word"]
        if not words:
            return {"text": "", "start": 0.0, "end": 0.0, "w": None, "starts": [], "turns": []}
        text = self._fix(clean(r.get("text") or " ".join(w["text"] for w in words)))
        start = round(words[0]["start"], 3)
        starts = [round(x["start"] - start, 3) for x in words]
        w = starts if len(words) == len(text.split()) else None
        out = {"text": text, "start": start, "end": words[-1]["end"], "w": w, "starts": starts, "turns": []}
        if diarize:
            runs = []
            for t in r.get("words", []):
                if t.get("type") == "word" and (not runs or t.get("speaker_id") != runs[-1]["who"]):
                    runs.append({"who": t.get("speaker_id"), "tokens": [], "words": []})
                if runs and t.get("type") in ("word", "spacing"):
                    runs[-1]["tokens"].append(t["text"])
                    if t["type"] == "word":
                        runs[-1]["words"].append(t)
            for run_ in runs:
                said = self._fix(clean("".join(run_["tokens"])))
                first = run_["words"][0]["start"]
                out["turns"].append({"start": round(first, 3), "end": run_["words"][-1]["end"], "text": said,
                                     "w": [round(x["start"] - first, 3) for x in run_["words"]]
                                     if len(run_["words"]) == len(said.split()) else None})
        return out

    def _fix(self, text):
        for wrong, right in self.fixes.items():
            if wrong.startswith("="):           # "=Father": only when that is all it heard
                text = right if text == wrong[1:] else text
            else:
                text = text.replace(wrong, right)
        return text

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
