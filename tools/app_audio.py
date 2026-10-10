"""The app's own sounds and its spoken help, the same in both apps: content/app/ (Android's assets/app/, the iPhone
app's Content/app/) and the manifest both read, content/app/app.json (AppManifest.kt, AppManifest.swift).

- The intro sting: a voice saying "Epic Audio Games!" over a short musical logo. The voice takes are ElevenLabs text
  to speech with a seed, the logo beds ElevenLabs sound effects; they're mixed here with ffmpeg: the bed ducks under
  the voice and fades out, and the mix is levelled to -16 LUFS with its peaks under -1.5 dBFS. -> sting.m4a
- The earcons: the microphone opening (two notes rising a fifth), closing (the same notes falling) and a pack
  installed (three notes rising). Synthesised here, with nothing but Python: no API, and the same bytes on every run.
  Four families: marimba (the default), glass, pluck and bubble. -> earcons/*.wav (Earcons.kt, CueBank.swift)
- The welcome and the help topics: tools/app_text.toml, read by Jessica (content.py's voice) one paragraph at a time,
  each with the paragraphs either side as context. -> tts/*.m4a, one clip per paragraph, and app.json, which has the
  text to show, the clips to play as map steps (docs/MAP_FORMAT.md, so the apps' players play them) with their word
  times, and which paragraph each clip reads.

Auditions come first: tools/cache/app/audition/index.html plays every variant, in context and as a phone speaker or a
Bluetooth headset would, with the command that picks it. Picks are kept in tools/app_audio_picks.json. Everything
ElevenLabs makes is cached in tools/cache/ (committed), so nothing is paid for twice. The key is ELEVENLABS_API_KEY,
from the environment or all-minigames-sites/alexa/.env; it is never printed. content/app/licences/ (the font's
licence) isn't this tool's: nothing here touches it.

Usage (from the repo root): py -3.13 tools/app_audio.py ...
  audition sting [--takes 2] [--music] [--voice ID | --bed ID]
  audition earcons [--elevenlabs]
  pick sting VOICE_ID BED_ID [--at S] [--duck DB] [--length S]   -> content/app/sting.m4a
  pick earcons FAMILY                                            -> content/app/earcons/
  build [--no-api] [--force]   the welcome and help clips, app.json; removes clips nothing plays any more
  check                        exit 1 if app.json doesn't match app_text.toml and the picks (validate.py runs it)
"""
import argparse
import base64
import concurrent.futures as cf
import hashlib
import html
import io
import json
import math
import random
import re
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import wave
from collections import Counter, namedtuple
from pathlib import Path

import content
from content import clean, duration, loudness, run, samples, slug
from voice_audition import api_key

try:
    import tomllib                  # Python 3.11 and later
except ImportError:                 # a Mac's own python3 (3.9), which validate.py runs on too: see check()
    tomllib = None

ROOT = content.ROOT
TEXT = ROOT / "tools" / "app_text.toml"
PICKS = ROOT / "tools" / "app_audio_picks.json"
CACHE = ROOT / "tools" / "cache" / "app"
AUDITION = CACHE / "audition"
OUT = ROOT / "content" / "app"
MANIFEST = OUT / "app.json"
VERSION = 1                 # of how app.json is made: part of its "source", so changing it asks for a build
PLATFORMS = ("ios", "android")
# The help topics, in order. The apps open some of them by id (a game's "How to play" is "voice").
TOPICS = ("getting-started", "voice", "screen-reader", "typing", "pausing", "packs", "headphones", "watch", "display",
          "contact")
# Words one app's text must never show: App Review (2.3.10) refuses an iPhone app that names Android, and Android
# players have no use for iPhone words either.
NOT_ON = {"ios": re.compile(r"\b(Android|TalkBack|Google|Play Store)\b", re.I),
          "android": re.compile(r"\b(iPhone|iPad|iOS|VoiceOver|Magic Tap|App Store|Apple)\b", re.I)}
# How long the spoken text should be, in seconds: (welcome, a help topic). Outside it, build and check warn.
SPOKEN = {"welcome": (15, 20), "help": (20, 45)}
BITEXACT = ["-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact"]
MP3 = ["-c:a", "libmp3lame", "-b:a", "128k", *BITEXACT]


class CacheMiss(Exception):
    """Something ElevenLabs would have to make, with --no-api."""


class Api:
    """Every ElevenLabs request goes through content.post (Content.tts's too): this counts them and, while not
    allowed (--no-api, and a pick's rebuild), refuses them."""

    def __init__(self, allowed=True):
        self.allowed = allowed
        self.calls = 0
        self.lock = threading.Lock()
        self.real = content.post
        content.post = self.post

    def post(self, path, *args, **kwargs):
        if not self.allowed:
            raise CacheMiss(f"{path.split('?')[0]}: not in the cache (and --no-api)")
        with self.lock:
            self.calls += 1
        return self.real(path, *args, **kwargs)


def balance():
    """The account's credits used this period and its limit, or None if they can't be read. Asking is free."""
    try:
        key = api_key()
    except SystemExit:                  # no key anywhere: nothing to report
        return None
    try:
        req = urllib.request.Request(content.API + "/v1/user/subscription", headers={"xi-api-key": key})
        with urllib.request.urlopen(req, timeout=30) as r:
            s = json.loads(r.read())
        return s["character_count"], s["character_limit"]
    except Exception:
        return None


def put(path, data):
    """Writes the bytes only when the file doesn't already hold them, so a rerun changes nothing. True if it wrote."""
    if path.exists() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def encoded(*args, suffix):
    """What ffmpeg makes of these arguments (inputs, filters, encoding), as bytes."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / f"out{suffix}"
        run(*args, out)
        return out.read_bytes()


def measure(path, af=""):
    """A file's integrated loudness (LUFS) and sample peak (dBFS), after the filters af if any."""
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
                        (af + "," if af else "") + "ebur128=peak=sample", "-f", "null", "-"],
                       capture_output=True, text=True)
    i = re.findall(r"I:\s+(-?[\d.]+) LUFS", p.stderr)
    peak = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", p.stderr)
    return (float(i[-1]) if i else -70.0), (float(peak[-1]) if peak and peak[-1] != "-inf" else -120.0)


def channels(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of",
                        "csv=p=0", str(path)], capture_output=True, text=True)
    return int(p.stdout.strip() or 1)


def rel(path):
    """A path as messages show it: from the repo root when it's inside the repo."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


# ----- Earcons -----

RATE = 48000
FAMILIES = ("marimba", "glass", "pluck", "bubble")
DEFAULT_FAMILY = "marimba"
EARCONS = ("listen-start", "listen-stop", "success")
G5, B5, D6 = 783.99, 987.77, 1174.66
# Each earcon's gesture, the same in every family: its notes (Hz), when each starts (s), its length (s) and its peak
# (dBFS). Listening started is two notes rising a fifth; stopped, the same two falling, shorter and 2 dB quieter; a
# pack installed, three notes rising (G major, so every fundamental is between 600 and 1300 Hz, where a phone's
# speaker and a call-quality Bluetooth link both carry it).
SHAPES = {
    "listen-start": ((G5, D6), (0.0, 0.062), 0.145, -3.0),
    "listen-stop": ((D6, G5), (0.0, 0.05), 0.118, -5.0),
    "success": ((G5, B5, D6), (0.0, 0.07, 0.14), 0.24, -3.0),
}
# The struck families' partials: (multiple of the note, level, decay time constant in s). The decays are short:
# a -3 dBFS peak over an RMS near -18 dBFS (as loud as the voice, never louder) makes a crisp tap, not a ring.
PARTIALS = {
    "marimba": ((1.0, 1.0, 0.010), (3.93, 0.3, 0.004)),   # a wooden bar: its tuned overtone dies almost at once
    "glass": ((1.0, 1.0, 0.013), (2.76, 0.45, 0.008)),    # struck glass: an inharmonic partial that rings on
}
# The bubble family's notes are water drops: each slides up into its note from 0.55 of it (G5's from 431 Hz) in 25 ms.
BUBBLE = (0.55, 0.025, 0.008)       # (where the slide starts, how long it takes, decay time constant)
# A Bluetooth headset's call audio (HFP narrowband) keeps 300-3400 Hz: partials fade out from 3000 Hz and are gone by
# 3400, so the sounds lose only brightness there.
BAND = (3000.0, 3400.0)


def _in_band(f):
    return 1.0 if f <= BAND[0] else max(0.0, (BAND[1] - f) / (BAND[1] - BAND[0]))


def _lowpass(x, fc):
    """A 12 dB/octave low-pass (RBJ biquad), run twice: 24 dB/octave."""
    w0 = 2 * math.pi * fc / RATE
    alpha, cw = math.sin(w0) / (2 * math.sqrt(0.5)), math.cos(w0)
    b0, b1, a0, a1, a2 = (1 - cw) / 2, 1 - cw, 1 + alpha, -2 * cw, 1 - alpha
    for _ in range(2):
        y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
        for v in x:
            out = (b0 * v + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2) / a0
            x2, x1, y2, y1 = x1, v, y1, out
            y.append(out)
        x = y
    return x


def _struck(family, f, n):
    x = [0.0] * n
    for ratio, level, tau in PARTIALS[family]:
        level *= _in_band(f * ratio)
        if level <= 0:
            continue
        w = 2 * math.pi * f * ratio / RATE
        for i in range(n):
            x[i] += level * math.sin(w * i) * math.exp(-i / (tau * RATE))
    return x


def _pluck(f, n, rng):
    """Karplus-Strong: a burst of noise (from a fixed seed) round a delay line one period long, losing a little each
    time, so it rings at f and dies away in about 30 ms. Low-passed below the narrowband edge."""
    size = max(2, round(RATE / f - 0.5))                  # the two-point average adds half a sample
    loss = math.exp(-(size + 0.5) / (0.03 * RATE))
    line = [rng.uniform(-1.0, 1.0) for _ in range(size)]
    mean = sum(line) / size
    line = [v - mean for v in line]
    for _ in range(2):                                    # a soft pick: the burst smoothed
        line = [(line[i] + line[i - 1]) / 2 for i in range(size)]
    x, p = [0.0] * n, 0
    for i in range(n):
        a, b = line[p], line[(p + 1) % size]
        x[i] = a
        line[p] = loss * 0.5 * (a + b)
        p = (p + 1) % size
    return _lowpass(x, 2600.0)


def _glide(f0, f1, n, glide, tau):
    """A sine sliding from f0 to f1 Hz (evenly in pitch) over glide seconds, dying away with time constant tau."""
    x, phase = [0.0] * n, 0.0
    for i in range(n):
        t = i / RATE
        x[i] = math.sin(phase) * math.exp(-t / tau)
        phase += 2 * math.pi * f0 * (f1 / f0) ** min(1.0, t / glide) / RATE
    return x


def _note(family, f, n, rng):
    """One note: n samples at f Hz, rising from silence at sample 0 through a 4 ms raised-cosine attack."""
    if family == "pluck":
        x = _pluck(f, n, rng)
    elif family == "bubble":
        x = _glide(f * BUBBLE[0], f, n, BUBBLE[1], BUBBLE[2])
    else:
        x = _struck(family, f, n)
    attack = int(0.004 * RATE)
    for i in range(min(attack, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / attack)
    return x


def earcon(family, name):
    """One earcon's sound (floats), before it's levelled: its notes added up, then a 10 ms raised-cosine fade that
    ends at exactly zero on the last sample. No silence before it, no tail after it."""
    notes, onsets, length, _ = SHAPES[name]
    n = round(length * RATE)
    rng = random.Random(f"{family}/{name}")              # a str seed is hashed the same way on every machine
    x = [0.0] * n
    for f, at in zip(notes, onsets):
        o = round(at * RATE)
        for i, v in enumerate(_note(family, f, n - o, rng)):
            x[o + i] += v
    fade = round(0.010 * RATE)
    for i in range(fade):
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade)
    return x


def _pcm16(x, peak_db, rng):
    """16-bit samples, the loudest at peak_db, with triangular dither from a fixed seed (silence stays exactly 0)."""
    top = max(abs(v) for v in x) or 1.0
    gain = 10 ** (peak_db / 20) * 32767 / top
    out = []
    for v in x:
        out.append(0 if v == 0.0 else max(-32768, min(32767, round(v * gain + rng.random() - rng.random()))))
    return out


def _wav(pcm):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    return buf.getvalue()


def synth(family):
    """A family's three earcons, as WAV bytes (16-bit mono 48 kHz): the same bytes every time."""
    if family not in FAMILIES:
        raise SystemExit(f"no earcon family {family!r}: {', '.join(FAMILIES)}")
    return {name: _wav(_pcm16(earcon(family, name), SHAPES[name][3], random.Random(f"{family}/{name}/dither")))
            for name in EARCONS}


def wav_samples(data):
    with wave.open(io.BytesIO(data)) as w:
        raw = w.readframes(w.getnframes())
    return struct.unpack(f"<{len(raw) // 2}h", raw)


def wav_stats(data):
    """Length (s), peak and RMS (dBFS) of a 16-bit mono WAV."""
    pcm = wav_samples(data)
    peak = max(abs(v) for v in pcm) or 1
    rms = math.sqrt(sum(v * v for v in pcm) / len(pcm)) or 1
    return len(pcm) / RATE, 20 * math.log10(peak / 32768), 20 * math.log10(rms / 32768)


# ElevenLabs' sound effects as earcons, for comparison on the audition page only (the earcons are synthesised).
EL_EARCONS = {
    "listen-start": "two soft marimba notes rising, short user interface sound, dry, no reverb",
    "listen-stop": "two soft marimba notes falling, short user interface sound, dry, no reverb",
    "success": "three soft marimba notes rising, cheerful success sound, short, dry, no reverb",
}


def el_earcon(name, take):
    """An ElevenLabs take of an earcon: cut from its first sound to at most 250 ms, with a 10 ms fade."""
    mp3 = sfx(EL_EARCONS[name], 0.5, take=take)
    pcm = samples(mp3, RATE)
    win = int(0.005 * RATE)
    start = next((i for i in range(0, max(0, len(pcm) - win), win)
                  if max(abs(v) for v in pcm[i:i + win]) > 32768 * 10 ** (-40 / 20)), 0)
    return encoded("-i", mp3, "-af", f"atrim=start={start / RATE:.4f}:duration=0.25,asetpts=PTS-STARTPTS,"
                   "afade=t=out:st=0.24:d=0.01", "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le",
                   *BITEXACT, suffix=".wav")


# ----- ElevenLabs: sound effects, music, voice takes (all cached) -----

def _key(*parts):
    return hashlib.sha1(json.dumps(parts).encode()).hexdigest()[:16]


def sfx(prompt, seconds, influence=0.6, take=1, model="eleven_text_to_sound_v2"):
    """An ElevenLabs sound effect: tools/cache/app/sfx/<key>.mp3, with its request in <key>.json. take: another try
    of the same prompt (each request sounds different)."""
    mp3 = CACHE / "sfx" / f"{_key(model, prompt, seconds, influence, take)}.mp3"
    if not mp3.exists():
        audio = content.post("/v1/sound-generation?output_format=mp3_44100_128",
                             {"text": prompt, "duration_seconds": seconds, "prompt_influence": influence,
                              "model_id": model}, raw=True)
        mp3.parent.mkdir(parents=True, exist_ok=True)
        mp3.with_suffix(".json").write_bytes((json.dumps(
            {"model": model, "prompt": prompt, "seconds": seconds, "influence": influence, "take": take,
             "made": time.strftime("%Y-%m-%d")}, indent=1) + "\n").encode())
        mp3.write_bytes(audio)
    return mp3


def music(prompt, ms=4500, take=1, model="music_v1"):
    """ElevenLabs music (instrumental): tools/cache/app/music/<key>.mp3, with its request in <key>.json."""
    mp3 = CACHE / "music" / f"{_key(model, prompt, ms, take)}.mp3"
    if not mp3.exists():
        audio = content.post("/v1/music?output_format=mp3_44100_128",
                             {"prompt": prompt, "music_length_ms": ms, "force_instrumental": True, "model_id": model},
                             raw=True)
        mp3.parent.mkdir(parents=True, exist_ok=True)
        mp3.with_suffix(".json").write_bytes((json.dumps(
            {"model": model, "prompt": prompt, "ms": ms, "take": take, "made": time.strftime("%Y-%m-%d")},
            indent=1) + "\n").encode())
        mp3.write_bytes(audio)
    return mp3


# The sting's voice takes: who, what they say, their ElevenLabs settings (stability, style) and the seeds tried. A
# take's id is the name and the seed: "jessica-a1".
TAKES = {
    "jessica-a": (content.VOICE, "Epic Audio Games!", 0.5, 0.15, (1, 2), "Jessica, as she hosts the games"),
    "jessica-b": (content.VOICE, "Welcome to Epic Audio Games!", 0.35, 0.4, (1, 2), "Jessica, welcoming"),
    "don-a": (content.DON, "Epic Audio Games!", 0.35, 0.45, (1, 2, 3), "Don, movie trailer voice"),
    "don-b": (content.DON, "Epic… Audio… Games!", 0.3, 0.6, (1, 2), "Don, a word at a time"),
}
DEFAULT_VOICES = ("jessica-a1", "don-a1")       # mixed with every bed by a plain "audition sting"


def takes():
    """Every voice take: id -> (voice, text, settings, seed, description)."""
    out = {}
    for name, (voice, text, stability, style, seeds, note) in TAKES.items():
        settings = {"stability": stability, "similarity_boost": 0.75, "style": style, "use_speaker_boost": True}
        for seed in seeds:
            out[f"{name}{seed}"] = (voice, text, settings, seed, note)
    return out


def voice_take(tid):
    """A voice take for the sting, with its character timings: tools/cache/app/voice/<voice>/<key>.mp3 and .json."""
    if tid not in takes():
        raise SystemExit(f"no voice take {tid!r}: {', '.join(takes())}")
    voice, text, settings, seed, _ = takes()[tid]
    key = _key(voice["id"], voice["model"], settings, text, seed)
    folder = CACHE / "voice" / voice["name"]
    mp3, info = folder / f"{key}.mp3", folder / f"{key}.json"
    if not mp3.exists():
        r = content.post(f"/v1/text-to-speech/{voice['id']}/with-timestamps?output_format=mp3_44100_128",
                         {"text": text, "model_id": voice["model"], "voice_settings": settings, "seed": seed})
        folder.mkdir(parents=True, exist_ok=True)
        info.write_text(json.dumps({"take": tid, "text": text, "settings": settings, "seed": seed,
                                    "alignment": r.get("alignment")}), encoding="utf-8")
        mp3.write_bytes(base64.b64decode(r["audio_base64"]))
    return mp3, json.loads(info.read_text(encoding="utf-8"))


def voice_span(mp3, info):
    """Where to cut a take, and where its words are (s): (from, words start, words end, to). The cut is 40 ms before
    the first character and 150 ms after the last, by ElevenLabs' character timings."""
    a = info.get("alignment") or {}
    chars, starts, ends = a.get("characters") or [], a.get("character_start_times_seconds") or [], \
        a.get("character_end_times_seconds") or []
    said = [i for i, c in enumerate(chars) if not c.isspace()]
    total = duration(mp3)
    if not said or len(starts) != len(chars):
        return 0.0, 0.0, total, total
    s0, s1 = starts[said[0]], ends[said[-1]]
    return max(0.0, s0 - 0.04), s0, s1, min(total, s1 + 0.15)


def take_text(tid):
    """What a take says, as the app shows it ("Epic Audio Games!", without Don's dramatic pauses)."""
    return clean(takes()[tid][1].replace("…", " "))


# The logo beds: an ElevenLabs sound effect prompt per style, about 3.2 s; a bed's id is the style and the take,
# "cinematic-1". With --music, ElevenLabs music in the same styles too: "music-cinematic-1".
BEDS = {
    "cinematic": "short cinematic logo sting, deep boom and orchestral brass hit swelling into a bright shimmering "
                 "resolve, no voice",
    "arcade": "playful video game logo jingle, bright synth arpeggio rising to a sparkling chime, no voice",
    "adventure": "taiko hit and whoosh, heroic horn swell, sparkle tail, no voice",
    "storybook": "harp glissando and celesta bells rising to a warm shimmer, no voice",
    "radio-drama": "old-time radio drama organ and timpani flourish, no voice",
}
BED_SECONDS = 3.2


def bed_prompt(bid):
    m = re.fullmatch(r"(music-)?([a-z-]+?)-(\d+)", bid)
    if not m or m.group(2) not in BEDS or int(m.group(3)) < 1:
        raise SystemExit(f"no bed {bid!r}: a style ({', '.join(BEDS)}) and a take, e.g. cinematic-1 or "
                         f"music-cinematic-1")
    style, take = m.group(2), int(m.group(3))
    if m.group(1):
        return "music", (f"short instrumental logo jingle for an audio game app, about four seconds, "
                         f"{BEDS[style].removesuffix(', no voice')}, ending on a bright resolved chord"), take
    return "sfx", BEDS[style], take


def bed_file(bid):
    kind, prompt, take = bed_prompt(bid)
    return music(prompt, take=take) if kind == "music" else sfx(prompt, BED_SECONDS, take=take)


# ----- The sting -----

VOICE_LUFS, BED_LUFS = -14.0, -18.0     # before ducking: the voice 4 dB over the bed, which then ducks under it
DUCK_DB = 8.0
RATIO = 6.0
STING_LUFS, STING_PEAK = -16.0, -1.5
ENCODE_STING = ["-ac", "2", "-ar", "48000", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", *BITEXACT]
# A phone's own speaker: one speaker (the mix folded to mono) with little below 500 Hz.
PHONE = "pan=mono|c0=0.5*c0+0.5*c1,highpass=f=500,highpass=f=500,lowpass=f=8000"


def onset(path):
    """When a bed's first sound starts: the first 10 ms over -30 dBFS."""
    pcm, win = samples(path, 16000), 160
    for i in range(0, len(pcm) - win, win):
        ms = sum(v * v for v in pcm[i:i + win]) / win
        if ms > 0 and 10 * math.log10(ms) - 90.31 > -30:
            return i / 16000
    return 0.0


def speech_level(path):
    """A voice's level while it speaks (dBFS): the mean power of its 20 ms windows within 20 dB of the loudest."""
    pcm, win = samples(path, 16000), 320
    powers = [sum(v * v for v in pcm[i:i + win]) / win for i in range(0, len(pcm) - win, win)]
    top = max(powers or [1.0])
    active = [p for p in powers if p > top / 100] or [top]
    return 10 * math.log10(sum(active) / len(active) or 1.0) - 90.31


def mix_sting(vid, bid, out_dir, at=None, duck=DUCK_DB, length=None):
    """Mixes a voice take over a bed, as content/app/sting.m4a would be, into out_dir: <vid>__<bid>.m4a and a
    phone-speaker preview. Returns what the audition page and app.json say about it.

    at (when the voice starts) defaults to the bed's first sound + 0.25 s, between 0.35 and 0.6 s; length to the
    voice's end + 0.9 s, between 2.8 and 3.5 s, and never so short that the fade (the last 0.4 s) reaches the voice.
    The bed ducks under the voice by about duck dB (a sidechain compressor whose threshold is set from the voice's
    level), then the mix is levelled to -16 LUFS, limited to -1.5 dBFS and encoded (AAC stereo, 96 kbps, 48 kHz)."""
    voice_mp3, info = voice_take(vid)
    t0, s0, s1, t1 = voice_span(voice_mp3, info)
    bed = bed_file(bid)
    # The pick command's options that make this mix again (only those chosen, not worked out).
    flags = ([f"--at {at:g}"] if at is not None else []) + ([f"--duck {duck:g}"] if duck != DUCK_DB else []) + \
        ([f"--length {length:g}"] if length is not None else [])
    if at is None:
        at = min(0.6, max(0.35, onset(bed) + 0.25))
    at = round(at, 3)
    voice_out = at + (t1 - t0)
    if length is None:
        length = min(3.5, max(2.8, voice_out + 0.9))
    length = round(max(length, voice_out + 0.45), 3)
    name = f"{vid}__{bid}"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        v, b, mixed, ducked = tmp / "voice.wav", tmp / "bed.wav", tmp / "mixed.wav", tmp / "ducked.wav"
        # The voice in the middle at its full level (ffmpeg's own mono-to-stereo would take 3 dB off it).
        run("-i", voice_mp3, "-af", f"atrim={t0:.3f}:{t1:.3f},asetpts=PTS-STARTPTS,aresample={RATE},"
            f"pan=stereo|c0=c0|c1=c0,afade=t=in:d=0.005,afade=t=out:st={max(0.0, t1 - t0 - 0.03):.3f}:d=0.03",
            "-c:a", "pcm_f32le", v)
        up = "" if channels(bed) >= 2 else "pan=stereo|c0=c0|c1=c0,"
        run("-i", bed, "-af", f"aresample={RATE},{up}apad,atrim=0:{length:.3f}", "-c:a", "pcm_f32le", b)
        vg = VOICE_LUFS - (loudness(v) or VOICE_LUFS)
        bg = BED_LUFS - (loudness(b) or BED_LUFS)
        # The compressor takes about (level - threshold) * (1 - 1/ratio) dB off the bed: a threshold that far under
        # the voice's speaking level ducks the bed by about duck dB.
        threshold = 10 ** ((speech_level(v) + vg - duck / (1 - 1 / RATIO)) / 20)
        threshold = min(1.0, max(0.001, threshold))
        graph = (f"[0:a]volume={bg:.2f}dB,afade=t=in:d=0.01,afade=t=out:st={length - 0.4:.3f}:d=0.4[bed];"
                 f"[1:a]volume={vg:.2f}dB,adelay={round(at * 1000)}:all=1,apad=whole_dur={length:.3f},"
                 f"atrim=0:{length:.3f},asplit=2[v][sc];"
                 f"[bed][sc]sidechaincompress=threshold={threshold:.5f}:ratio={RATIO}:attack=10:release=250,"
                 "asplit=2[d][dout];"
                 "[d][v]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.84:level=false[m]")
        run("-i", b, "-i", v, "-filter_complex", graph, "-map", "[m]", "-c:a", "pcm_f32le", mixed,
            "-map", "[dout]", "-c:a", "pcm_f32le", ducked)
        # How far the voice stands over the ducked bed while it speaks (both before levelling, which moves both).
        window = f"atrim={at + s0 - t0:.3f}:{at + s1 - t0:.3f}"
        over = measure(v, f"adelay={round(at * 1000)}:all=1,{window},volume={vg:.2f}dB")[0] - measure(ducked, window)[0]
        data, lufs, peak = level(mixed)
    out = out_dir / f"{name}.m4a"
    put(out, data)
    put(out_dir / f"{name}-phone.mp3", encoded("-i", out, "-af", PHONE, *MP3, suffix=".mp3"))
    mono = measure(out, "pan=mono|c0=0.5*c0+0.5*c1")[0]
    return {"voice": vid, "bed": bid, "text": take_text(vid), "at": at, "duck": duck, "length": length,
            "voiceAt": round(at + s0 - t0, 3), "voiceEnd": round(at + s1 - t0, 3), "dur": round(duration(out), 3),
            "lufs": round(lufs, 1), "peak": round(peak, 1),
            # Folded to mono, a centred sound measures 3 dB under its stereo self: more than that is lost to phase.
            "monoLoss": round(lufs - 3.01 - mono, 1), "voiceOverBed": round(over, 1),
            "file": name, "flags": flags}


def level(mixed):
    """The mix levelled to -16 LUFS with its peaks at most -1.5 dBFS once encoded: (bytes, LUFS, peak). The limiter
    can take some loudness with it, and the encoder can overshoot a little, so it's measured and done again."""
    gain, limit = STING_LUFS - (loudness(mixed) or STING_LUFS), 0.84
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "sting.m4a"
        for _ in range(5):
            run("-i", mixed, "-af", f"volume={gain:.2f}dB,alimiter=limit={limit:.4f}:level=false", *ENCODE_STING, out)
            lufs, peak = measure(out)
            if peak > STING_PEAK:
                limit *= 10 ** ((STING_PEAK - peak - 0.1) / 20)
            elif abs(lufs - STING_LUFS) > 0.3:
                gain += STING_LUFS - lufs
            else:
                break
        return out.read_bytes(), lufs, peak


def sting_ok(m):
    """What's wrong with a mix, against content/app/sting.m4a's rules; [] when nothing is."""
    bad = []
    if not 2.8 <= m["dur"] <= 3.6:
        bad.append(f"{m['dur']} s long (2.8-3.5)")
    if abs(m["lufs"] - STING_LUFS) > 0.5:
        bad.append(f"{m['lufs']} LUFS (-16)")
    if m["peak"] > STING_PEAK:
        bad.append(f"peaks at {m['peak']} dBFS (-1.5)")
    if m["monoLoss"] > 2:
        bad.append(f"loses {m['monoLoss']} dB folded to mono (2)")
    return bad


# ----- Auditions -----

def question():
    """A question Jessica asks in a game, to hear the listening sounds after (a turn as the player hears it)."""
    want = ROOT / "content" / "leaning-tower-of-pizza" / "tts" / "welcome-back-pinocchio-want-to-play-eb5777.m4a"
    if want.exists():
        return want, "Welcome back Pinocchio! Want to play Battle or Challenge mode?"
    for path in sorted((ROOT / "games").glob("*/map.json")):
        for node in json.loads(path.read_text(encoding="utf-8"))["nodes"].values():
            for s in node.get("say") or []:
                line = (s.get("lines") or [{}])[0]
                if str(s.get("play", "")).startswith("tts/") and line.get("text", "").endswith("?"):
                    f = next((p for p in (ROOT / "content" / path.parent.name).glob(f"{s['play']}.*")), None)
                    if f:
                        return f, line["text"]
    raise SystemExit("no question of Jessica's in content/ to put the earcons after")


def demo(q, start, stop):
    """A turn's end as the player hears it: the question's last 3 s, 0.35 s, the listening sound, 1.2 s for the
    answer, the stopped sound. MP3 bytes."""
    q0 = max(0.0, duration(q) - 3.0)
    fmt = f"aresample={RATE},aformat=sample_fmts=fltp:channel_layouts=mono"
    graph = (f"[0:a]atrim=start={q0:.3f},asetpts=PTS-STARTPTS,{fmt}[q];[1:a]{fmt}[s];[2:a]{fmt}[e];"
             f"anullsrc=r={RATE}:cl=mono,atrim=0:0.35,{fmt}[g1];anullsrc=r={RATE}:cl=mono,atrim=0:1.2,{fmt}[g2];"
             f"anullsrc=r={RATE}:cl=mono,atrim=0:0.6,{fmt}[g3];[q][g1][s][g2][e][g3]concat=n=6:v=0:a=1[d]")
    return encoded("-i", q, "-i", start, "-i", stop, "-filter_complex", graph, "-map", "[d]", *MP3, suffix=".mp3")


# Over a call-quality Bluetooth link (HFP narrowband): 300-3400 Hz, 8 kHz.
NARROWBAND = "highpass=f=300,highpass=f=300,lowpass=f=3400,lowpass=f=3400,aresample=8000,aresample=22050"


def above_band(path):
    """How much of a sound is above 3.4 kHz (dB under the whole), which a narrowband link loses."""
    def rms(af):
        p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
                            (af + "," if af else "") + "astats=measure_perchannel=none:measure_overall=RMS_level",
                            "-f", "null", "-"], capture_output=True, text=True)
        m = re.findall(r"RMS level dB:\s+(-?[\d.]+|-inf)", p.stderr)
        return float(m[-1]) if m and m[-1] != "-inf" else -120.0
    return round(rms("highpass=f=3400,highpass=f=3400,highpass=f=3400") - rms(""), 1)


def audition_earcons(elevenlabs=False):
    q, said = question()
    index = {"question": {"file": rel(q), "text": said}, "families": {}, "elevenlabs": {}}
    for family in FAMILIES:
        folder = AUDITION / "earcons" / family
        sounds = synth(family)
        info = {}
        for name, data in sounds.items():
            put(folder / f"{name}.wav", data)
            secs, peak, rms = wav_stats(data)
            info[name] = {"ms": round(secs * 1000), "peak": round(peak, 1), "rms": round(rms, 1),
                          "above": above_band(folder / f"{name}.wav")}
        put(folder / "demo.mp3", demo(q, folder / "listen-start.wav", folder / "listen-stop.wav"))
        put(folder / "demo-narrowband.mp3", encoded("-i", folder / "demo.mp3", "-af", NARROWBAND, "-ar", "22050",
                                                    "-c:a", "libmp3lame", "-b:a", "48k", *BITEXACT, suffix=".mp3"))
        index["families"][family] = info
        print(f"{family}: " + ", ".join(f"{n} {i['ms']} ms, peak {i['peak']}, RMS {i['rms']} dBFS, "
                                       f"{i['above']} dB above 3.4 kHz" for n, i in info.items()))
    if elevenlabs:
        folder = AUDITION / "earcons" / "elevenlabs"
        for name in EARCONS:
            for take in (1, 2):
                put(folder / f"{name}-{take}.wav", el_earcon(name, take))
                index["elevenlabs"][f"{name}-{take}"] = {"prompt": EL_EARCONS[name]}
    else:
        old = _read_json(AUDITION / "earcons" / "index.json")
        index["elevenlabs"] = old.get("elevenlabs", {})
    put(AUDITION / "earcons" / "index.json", (json.dumps(index, indent=1, ensure_ascii=False) + "\n").encode())
    write_page()


def audition_sting(n_takes=2, with_music=False, voice=None, bed=None):
    vids = list(takes())
    for vid in vids:                     # every take, to hear alone and to mix later with --voice
        voice_take(vid)
    beds = [f"{style}-{t}" for style in BEDS for t in range(1, n_takes + 1)]
    if with_music:
        beds += [f"music-{style}-{t}" for style in BEDS for t in range(1, n_takes + 1)]
    if bed:
        bed_prompt(bed)
        beds = [bed]
    for b in beds:
        bed_file(b)
    if voice:
        voice_take(voice)
        pairs = [(voice, b) for b in beds]
    elif bed:
        pairs = [(v, bed) for v in vids]
    else:
        pairs = [(v, b) for v in DEFAULT_VOICES for b in beds]
    index_file = AUDITION / "sting" / "index.json"
    index = _read_json(index_file)
    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for m in pool.map(lambda p: mix_sting(*p, AUDITION / "sting"), pairs):
            index[m["file"]] = m
            bad = sting_ok(m)
            print(f"{m['file']}: {m['dur']} s, voice {m['voiceAt']}-{m['voiceEnd']} s, {m['lufs']} LUFS, peak "
                  f"{m['peak']} dBFS, {max(0.0, m['monoLoss'])} dB lost folded to mono, voice "
                  f"{m['voiceOverBed']} dB over the bed" + (f"  ! {'; '.join(bad)}" if bad else ""))
    put(index_file, (json.dumps(dict(sorted(index.items())), indent=1, ensure_ascii=False) + "\n").encode())
    write_page()


def _read_json(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


# ----- The audition page -----

PAGE_STYLE = """
:root { color-scheme: light dark; --bg: #F3F5FB; --surface: #FFFFFF; --text: #0B1430; --muted: #3B4566;
  --heading: #16275E; --outline: #6B7699; --ok: #0F5C33; --bad: #A4161A; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0B1430; --surface: #16275E; --text: #F6F8FF; --muted: #C9D2F0; --heading: #FFD54F;
    --outline: #8E9CCB; --ok: #8FE3B0; --bad: #FFB4AB; }
}
* { box-sizing: border-box; }
body { margin: 0; padding: 16px; background: var(--bg); color: var(--text);
  font: 18px/1.45 "Atkinson Hyperlegible Next", system-ui, sans-serif; }
main { max-width: 1180px; margin: 0 auto; }
h1, h2, h3 { color: var(--heading); line-height: 1.25; margin: 1.4em 0 0.4em; }
h1 { margin-top: 0.4em; }
p, li { max-width: 75ch; }
.muted { color: var(--muted); }
.card { background: var(--surface); border: 2px solid var(--outline); border-radius: 12px; padding: 12px 16px;
  margin: 12px 0; }
.scroll { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; vertical-align: top; padding: 8px; border-top: 2px solid var(--outline); }
th { white-space: nowrap; }
audio { width: 250px; max-width: 100%; display: block; }
code { font-size: 15px; overflow-wrap: anywhere; }
.ok { color: var(--ok); font-weight: 700; }
.bad { color: var(--bad); font-weight: 700; }
.picked { border-color: var(--ok); border-width: 4px; }
"""


def _audio(src, label):
    return f'<audio controls preload="none" src="{html.escape(src)}" aria-label="{html.escape(label)}"></audio>'


def _cache_src(path):
    """A cache file (a voice take, a bed) as the page, in tools/cache/app/audition/, links to it."""
    return "../" + Path(path).resolve().relative_to(CACHE.resolve()).as_posix()


def _row(head, *cells):
    return f'<tr><th scope="row">{head}</th>' + "".join(f"<td>{c}</td>" for c in cells) + "</tr>"


def _sting_rows(mixes, sting_pick):
    """A voice take's mixes, a row each: the sting, its phone-speaker preview, its numbers and its pick command."""
    rows = []
    for m in sorted(mixes, key=lambda m: m["bed"]):
        bad = sting_ok(m)
        picked = sting_pick.get("voice") == m["voice"] and sting_pick.get("bed") == m["bed"]
        name = f'{m["voice"]} over {m["bed"]}'
        numbers = (f'{m["dur"]} s; voice {m["voiceAt"]} to {m["voiceEnd"]} s; {m["lufs"]} LUFS, peak {m["peak"]} '
                   f'dBFS; voice over bed {m["voiceOverBed"]} dB; mono fold {max(0.0, m["monoLoss"])} dB. '
                   + (f'<span class="bad">Check: {html.escape("; ".join(bad))}</span>' if bad
                      else '<span class="ok">Checks pass</span>'))
        command = " ".join(["py -3.13 tools/app_audio.py pick sting", m["voice"], m["bed"], *(m.get("flags") or [])])
        rows.append(_row(html.escape(m["bed"]) + (" (picked)" if picked else ""),
                         _audio(f'sting/{m["file"]}.m4a', name),
                         _audio(f'sting/{m["file"]}-phone.mp3', f"{name}, phone speaker"),
                         numbers, f"<code>{html.escape(command)}</code>"))
    return rows


def _earcon_card(family, info, picked):
    rows = [_row(name, _audio(f"earcons/{family}/{name}.wav", f"{family}, {name}"),
                 f'{i["ms"]} ms; peak {i["peak"]} dBFS; RMS {i["rms"]} dBFS; above 3.4 kHz {i["above"]} dB')
            for name, i in info.items()]
    rows += [_row("In a game", _audio(f"earcons/{family}/demo.mp3", f"{family}, in a game"),
                  "A question, the listening sound, an answer's pause, the stopped sound"),
             _row("Bluetooth headset", _audio(f"earcons/{family}/demo-narrowband.mp3",
                                              f"{family}, over a Bluetooth headset"),
                  "The same, over a call-quality link")]
    return [f'<div class="card{" picked" if picked else ""}"><h3 style="margin-top:0">{html.escape(family)}'
            f'{" (picked)" if picked else ""}</h3><div class="scroll"><table><tbody>', *rows,
            f"</tbody></table></div><p>Pick it: <code>py -3.13 tools/app_audio.py pick earcons {family}</code></p>"
            "</div>"]


def write_page():
    """tools/cache/app/audition/index.html: every sting and earcon variant made so far, the picks, and the commands
    that pick. Made from the auditions' index.json files, so a later audition adds to it."""
    picks = load_picks()
    stings = _read_json(AUDITION / "sting" / "index.json")
    ears = _read_json(AUDITION / "earcons" / "index.json")
    sting_pick = picks.get("sting") or {}
    picked_sting = (html.escape(f'{sting_pick["voice"]} over {sting_pick["bed"]}') if sting_pick
                    else "none yet (the intro shows without sound)")
    h = ['<!doctype html>', '<html lang="en">', '<head>', '<meta charset="utf-8">',
         '<meta name="viewport" content="width=device-width, initial-scale=1">', '<title>App sounds</title>',
         f'<style>{PAGE_STYLE}</style>', '</head>', '<body>', '<main>', '<h1>App sounds: auditions</h1>',
         '<p>Listen with headphones, and to the phone-speaker and Bluetooth previews too: players hear these all '
         'three ways. Each variant has the command that picks it; run it from the repo root. A pick writes the file '
         'into <code>content/app/</code> and updates <code>app.json</code>.</p>',
         '<div class="card"><h2 style="margin-top:0">Picked now</h2><ul>', f'<li>Sting: {picked_sting}</li>',
         f'<li>Earcons: {html.escape(picks.get("earcons", DEFAULT_FAMILY))}</li>', '</ul></div>']
    # The stings, by voice take.
    h += ['<h2 id="sting">Intro sting</h2>',
          '<p>A voice over a logo bed, as <code>content/app/sting.m4a</code> would be: the bed ducks under the voice '
          'and fades out over its last 0.4 s; the mix is levelled to -16 LUFS with peaks at most -1.5 dBFS (AAC '
          'stereo). The phone-speaker preview is the same sting folded to mono with nothing under 500 Hz. '
          '<strong>Voice over bed</strong> is how far the voice stands above the ducked bed while it speaks (more '
          'is clearer); <strong>mono fold</strong> is what a one-speaker phone loses beyond the usual 3 dB (over 2 dB '
          'is flagged).</p>']
    by_voice = {}
    for m in stings.values():
        by_voice.setdefault(m["voice"], []).append(m)
    all_takes = takes()
    for vid in [v for v in all_takes if v in by_voice]:
        voice, text, settings, seed, note = all_takes[vid]
        mp3, _ = voice_take(vid)
        h += [f'<h3>{html.escape(vid)}: “{html.escape(take_text(vid))}”</h3>',
              f'<p class="muted">{html.escape(note)}; stability {settings["stability"]}, style {settings["style"]}, '
              f'seed {seed}.</p>', _audio(_cache_src(mp3), f"{vid}, the voice alone"),
              '<div class="scroll"><table><thead><tr><th scope="col">Bed</th><th scope="col">Sting</th>'
              '<th scope="col">Phone speaker</th><th scope="col">Numbers</th><th scope="col">Pick it</th></tr>'
              '</thead><tbody>', *_sting_rows(by_voice[vid], sting_pick), '</tbody></table></div>']
    # Voice takes not mixed yet, and the beds alone.
    unmixed = [v for v in all_takes if v not in by_voice and _cached_take(v)]
    if unmixed:
        h += ['<h3>More voice takes</h3>', '<p>Not mixed yet: mix one with every bed with '
              '<code>py -3.13 tools/app_audio.py audition sting --voice ID</code>.</p><ul>']
        for vid in unmixed:
            mp3, _ = voice_take(vid)
            h.append(f'<li>{html.escape(vid)}: “{html.escape(take_text(vid))}” ({html.escape(all_takes[vid][4])}) '
                     f'{_audio(_cache_src(mp3), vid)}</li>')
        h.append('</ul>')
    beds = sorted({m["bed"] for m in stings.values()})
    if beds:
        h += ['<h3>The beds alone</h3>', '<p class="muted">ElevenLabs sound effects, as generated (before ducking '
              'and levelling).</p><ul>']
        for b in beds:
            prompt = bed_prompt(b)[1]
            h.append(f'<li>{html.escape(b)}: “{html.escape(prompt)}” '
                     f'{_audio(_cache_src(bed_file(b)), b + " alone")}</li>')
        h.append('</ul>')
    # The earcons, by family.
    if ears.get("families"):
        q = ears.get("question", {})
        h += ['<h2 id="earcons">Earcons</h2>',
              '<p>The sounds of the microphone opening and closing, and of a pack installed. The in-game demo plays '
              f'the end of a question (“{html.escape(q.get("text", ""))}”), the listening sound, 1.2 s for an answer, '
              'then the stopped sound; the Bluetooth demo is the same through a call-quality headset link (300 to '
              '3400 Hz). The listening sound must be easy to hear over the story and never sound like a word. '
              '<strong>Above 3.4 kHz</strong> is how much of a sound such a link loses.</p>']
        for family, info in ears["families"].items():
            h += _earcon_card(family, info, picks.get("earcons", DEFAULT_FAMILY) == family)
        if ears.get("elevenlabs"):
            h += ['<h3>ElevenLabs takes, for comparison</h3>', '<p class="muted">Sound effects cut to 250 ms. They '
                  'can\'t be picked: the earcons are synthesised, so they are the same bytes every time and stay '
                  'inside the band a headset carries.</p><ul>']
            for take, i in ears["elevenlabs"].items():
                h.append(f'<li>{html.escape(take)}: “{html.escape(i["prompt"])}” '
                         f'{_audio(f"earcons/elevenlabs/{take}.wav", "ElevenLabs " + take)}</li>')
            h.append('</ul>')
    h += ['</main>', '</body>', '</html>', '']
    put(AUDITION / "index.html", "\n".join(h).encode("utf-8"))


def _cached_take(vid):
    voice, text, settings, seed, _ = takes()[vid]
    return (CACHE / "voice" / voice["name"] / f"{_key(voice['id'], voice['model'], settings, text, seed)}.mp3").exists()


# ----- Picks -----

def load_picks():
    data = _read_json(PICKS)
    return {k: v for k, v in data.items() if not k.startswith("_")}


def save_picks(picks):
    data = {"_doc": "The owner's picks from tools/cache/app/audition/index.html, written by "
                    "py -3.13 tools/app_audio.py pick ... (earcons: a family; sting: the mix content/app/sting.m4a "
                    "is, and its sha256).", **picks}
    put(PICKS, (json.dumps(data, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))


def pick_sting(vid, bid, at=None, duck=DUCK_DB, length=None):
    with tempfile.TemporaryDirectory() as tmp:
        m = mix_sting(vid, bid, Path(tmp), at=at, duck=duck, length=length)
        data = (Path(tmp) / f"{m['file']}.m4a").read_bytes()
    bad = sting_ok(m)
    if bad:
        print(f"  ! {'; '.join(bad)}")
    put(OUT / "sting.m4a", data)
    picks = load_picks()
    picks["sting"] = {k: m[k] for k in ("voice", "bed", "at", "duck", "length", "text", "dur", "voiceAt", "voiceEnd",
                                        "lufs", "peak", "monoLoss", "voiceOverBed")}
    picks["sting"]["sha256"] = hashlib.sha256(data).hexdigest()
    save_picks(picks)
    write_page()                        # the page marks the pick
    print(f"sting: {vid} over {bid}, {m['dur']} s, {m['lufs']} LUFS, peak {m['peak']} dBFS -> {rel(OUT / 'sting.m4a')}")


def pick_earcons(family):
    sounds = synth(family)
    for name, data in sounds.items():
        put(OUT / "earcons" / f"{name}.wav", data)
    picks = load_picks()
    picks["earcons"] = family
    save_picks(picks)
    write_page()
    print(f"earcons: {family} -> {rel(OUT / 'earcons')}")


# ----- The help text -----

Para = namedtuple("Para", "text speak")          # speak: what's read when it isn't the text shown, else None
Cue = namedtuple("Cue", "name")                  # an earcon played inside the spoken text
Entry = namedtuple("Entry", "kind id platform title summary items links")
CUES = ("listen-start", "listen-stop", "success")
TAIL = 0.35                 # the silence a clip keeps after its last sound (s)
# Silence between the parts of a spoken topic (s), after a clip's own TAIL.
GAPS = {("para", "para"): 0.3, ("para", "cue"): 0.2, ("cue", "para"): 0.6, ("cue", "cue"): 0.4}


def spoken(p):
    return p.speak or p.text


def read_text():
    """tools/app_text.toml, checked: (the document, a list of what's wrong with it)."""
    errors = []
    if tomllib is None:
        return {}, ["reading it needs Python 3.11 or later (py -3.13 on the PC)"]
    try:
        doc = tomllib.loads(TEXT.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as e:
        return {}, [str(e)]

    def keys(table, allowed, where):
        for k in table:
            if k not in allowed:
                errors.append(f"{where}: unknown key {k!r}")

    keys(doc, {"welcome", "help"}, rel(TEXT))
    welcome = doc.get("welcome")
    if not isinstance(welcome, dict):
        errors.append("no [welcome]")
    else:
        keys(welcome, {"title", "paragraphs"}, "welcome")
    ids = []
    if not isinstance(doc.get("help", []), list) or not all(isinstance(t, dict) for t in doc.get("help", [])):
        return doc, errors + ["each help topic is a [[help]] table"]
    for i, t in enumerate(doc.get("help") or []):
        where = f"help topic {t.get('id') or i + 1}"
        keys(t, {"id", "title", "summary", "paragraphs", "links", *PLATFORMS}, where)
        for p in PLATFORMS:
            if p in t:
                keys(t[p], {"title", "summary", "paragraphs", "links"}, f"{where} [{p}]")
        if not re.fullmatch(r"[a-z0-9-]+", str(t.get("id", ""))):
            errors.append(f"{where}: an id of lower-case letters, digits and hyphens")
        ids.append(t.get("id"))
    for tid in TOPICS:
        if tid not in ids:
            errors.append(f"no help topic {tid!r} (the apps link to every one)")
    for tid, n in Counter(ids).items():
        if n > 1:
            errors.append(f"help topic {tid!r} twice")
    if not errors:
        welcomes = [entries(doc, p, errors)[0] for p in PLATFORMS]
        if welcomes[0][3:] != welcomes[1][3:]:
            errors.append("welcome: the same on both apps (app.json has one), so no ios or android paragraphs")
    return doc, list(dict.fromkeys(errors))         # a shared paragraph's problem is found once per app


def _item(x, where, errors):
    if isinstance(x, str) and clean(x):
        return Para(clean(x), None)
    if isinstance(x, dict) and set(x) <= {"text", "speak"} and isinstance(x.get("text"), str) and clean(x["text"]):
        speak = clean(x["speak"]) if isinstance(x.get("speak"), str) and clean(x["speak"]) else None
        return Para(clean(x["text"]), speak if speak != clean(x["text"]) else None)
    if isinstance(x, dict) and set(x) == {"cue"}:
        if x["cue"] in CUES:
            return Cue(x["cue"])
        errors.append(f"{where}: no earcon {x['cue']!r} ({', '.join(CUES)})")
        return None
    errors.append(f"{where}: a paragraph is a text, {{text, speak}}, {{cue}} or {{ios, android}}, not {x!r}")
    return None


def entries(doc, platform, errors):
    """The welcome and each help topic as the app on this platform shows and says them."""
    out = []
    sections = [("welcome", "welcome", doc.get("welcome") or {})] + \
        [("help", t.get("id"), t) for t in doc.get("help") or []]
    for kind, tid, section in sections:
        own = section.get(platform) or {}
        where = "welcome" if kind == "welcome" else f"help topic {tid}"
        title = own.get("title", section.get("title"))
        summary = own.get("summary", section.get("summary")) if kind == "help" else None
        raw = own.get("paragraphs", section.get("paragraphs"))
        links = own.get("links", section.get("links", [])) if kind == "help" else []
        if not isinstance(title, str) or not title.strip():
            errors.append(f"{where}: no title for {platform}")
        if kind == "help" and (not isinstance(summary, str) or not summary.strip()):
            errors.append(f"{where}: no summary for {platform}")
        items = []
        for k, x in enumerate(raw if isinstance(raw, list) else []):
            if isinstance(x, dict) and set(x) & set(PLATFORMS):
                if not set(x) <= set(PLATFORMS):
                    errors.append(f"{where} paragraph {k + 1}: a platform pair has only ios and android")
                    continue
                x = x.get(platform)
                if x is None:
                    continue
            item = _item(x, f"{where} paragraph {k + 1}", errors)
            if item:
                items.append(item)
        if not any(isinstance(x, Para) for x in items):
            errors.append(f"{where}: no paragraphs for {platform}")
        if not isinstance(links, list):
            errors.append(f"{where}: links is a list")
            links = []
        for link in links:
            if not (isinstance(link, dict) and set(link) == {"label", "url"} and str(link["label"]).strip()
                    and re.match(r"(https://|mailto:)\S+$", str(link["url"]))):
                errors.append(f"{where}: a link is {{label, url}} with an https: or mailto: url, not {link!r}")
        shown = [title or "", summary or ""] + [t for x in items if isinstance(x, Para) for t in (x.text, spoken(x))]
        shown = list(dict.fromkeys(shown + [str(link.get("label", "")) for link in links if isinstance(link, dict)]))
        for s in shown:
            bad = NOT_ON[platform].search(s)
            if bad:
                errors.append(f"{where}: {bad.group(0)!r} in what the {platform} app shows or says: {s!r}")
        for s in shown:
            if "<" in s or ">" in s:
                errors.append(f"{where}: no markup in the text: {s!r}")
        out.append(Entry(kind, tid, platform, (title or "").strip(), (summary or "").strip() or None, items,
                         [{"label": str(link["label"]).strip(), "url": link["url"]} for link in links
                          if isinstance(link, dict) and "label" in link and "url" in link]))
    return out


def contexts(all_entries):
    """Each paragraph's context: the spoken paragraphs either side of it in its topic. A paragraph both apps say keeps
    only the context they share, so it's rendered once. {(id, para, n-th): {"previous_text", "next_text"}}."""
    seen = {}
    for e in all_entries:
        paras = [x for x in e.items if isinstance(x, Para)]
        count = Counter()
        for i, p in enumerate(paras):
            k = (e.id, p, count[p])
            count[p] += 1
            prev = spoken(paras[i - 1]) if i > 0 else None
            nxt = spoken(paras[i + 1]) if i + 1 < len(paras) else None
            seen.setdefault(k, {})[e.platform] = (prev, nxt)
    out = {}
    for k, by in seen.items():
        prevs, nexts = {v[0] for v in by.values()}, {v[1] for v in by.values()}
        out[k] = {"previous_text": prevs.pop() if len(prevs) == 1 else None,
                  "next_text": nexts.pop() if len(nexts) == 1 else None}
    return out


def source_hash():
    """What app.json is made from: the text, the picks and this tool's VERSION (line endings don't count)."""
    text = TEXT.read_text(encoding="utf-8").replace("\r\n", "\n") if TEXT.exists() else ""
    picks = json.dumps(load_picks(), sort_keys=True)
    return hashlib.sha1(f"{VERSION}\n{text}\n{picks}".encode("utf-8")).hexdigest()[:16]


# ----- Build -----

def demo_copy(cue):
    """An earcon as AAC (mono 48 kHz), for a help clip that plays it: the apps' players only take .m4a, .mp3 and
    .opus."""
    return encoded("-i", OUT / "earcons" / f"{cue}.wav", "-ac", "1", "-ar", str(RATE), "-c:a", "aac", "-b:a", "64k",
                   "-movflags", "+faststart", *BITEXACT, suffix=".m4a")


def build(force=False):
    """Everything content/app/ needs from the text and the picks: the earcons of the picked family, the clips, the
    earcon copies the clips play, app.json. Writes only what changed; removes clips nothing plays any more."""
    doc, errors = read_text()
    if errors:
        raise SystemExit("tools/app_text.toml:\n" + "\n".join(f"  x {e}" for e in errors))
    picks = load_picks()
    family = picks.get("earcons", DEFAULT_FAMILY)
    wrote = []
    for name, data in synth(family).items():
        if put(OUT / "earcons" / f"{name}.wav", data):
            wrote.append(f"earcons/{name}.wav")
    per = {p: entries(doc, p, []) for p in PLATFORMS}
    ctx = contexts(per["ios"] + per["android"])
    cues = sorted({x.name for es in per.values() for e in es for x in e.items if isinstance(x, Cue)})
    for cue in cues:
        if put(OUT / "earcons" / f"{cue}-demo.m4a", demo_copy(cue)):
            wrote.append(f"earcons/{cue}-demo.m4a")
    demo_dur = {cue: round(duration(OUT / "earcons" / f"{cue}-demo.m4a"), 3) for cue in cues}

    # The clips: one per paragraph, each with its context, rendered (or found) in parallel. Each ends 0.35 s after
    # its last sound, so the pauses between paragraphs are the same everywhere. With force, every clip is encoded
    # again from the cache, into a folder of its own first, so a build that fails halfway leaves content/app/ whole.
    scratch = tempfile.TemporaryDirectory()
    c = content.Content("app", "", trim=True, tail=TAIL, out=Path(scratch.name) if force else None)
    jobs = {}
    for es in per.values():
        for e in es:
            count = Counter()
            for x in e.items:
                if isinstance(x, Para):
                    k = (e.id, x, count[x])
                    count[x] += 1
                    cx = ctx[k]
                    jobs[(x, cx["previous_text"], cx["next_text"])] = None
    before = {f.name for f in (OUT / "tts").glob("*")}
    with scratch, cf.ThreadPoolExecutor(max_workers=6) as pool:
        made = pool.map(lambda j: c.tts(j[0].text, speak=j[0].speak,
                                        context={"previous_text": j[1], "next_text": j[2]}), list(jobs))
        for j, step in zip(list(jobs), made):
            jobs[j] = step
        for f in sorted(Path(scratch.name, "tts").glob("*")):
            if put(OUT / "tts" / f.name, f.read_bytes()):
                wrote.append(f"tts/{f.name}")
    wrote += sorted(f"tts/{f.name}" for f in (OUT / "tts").glob("*") if f.name not in before and not force)

    def entry_json(e):
        text, steps, clips, last = [], [], [], None
        count = Counter()
        for x in e.items:
            kind = "para" if isinstance(x, Para) else "cue"
            if last:
                steps.append({"pause": GAPS[(last, kind)]})
            if kind == "para":
                k = (e.id, x, count[x])
                count[x] += 1
                cx = ctx[k]
                text.append(x.text)
                steps.append(jobs[(x, cx["previous_text"], cx["next_text"])])
                clips.append(len(text) - 1)
            else:
                steps.append({"play": f"earcons/{x.name}-demo", "dur": demo_dur[x.name], "lines": [], "sfx": True})
                clips.append(-1)
            last = kind
        out = {"title": e.title}
        if e.kind == "help":
            out = {"id": e.id, **out, "summary": e.summary}
        out.update({"text": text, "clipParagraph": clips, "steps": steps})
        if e.kind == "help":
            out["links"] = e.links
        return out

    welcome = {p: entry_json(per[p][0]) for p in PLATFORMS}
    if welcome["ios"] != welcome["android"]:
        raise SystemExit("the welcome is the same on both apps: no ios or android paragraphs in it")
    help_ = []
    for ios, android in zip(per["ios"][1:], per["android"][1:]):
        a, b = entry_json(ios), entry_json(android)
        if a == b:
            help_.append(a)
        else:
            help_ += [{"id": a["id"], "platform": "ios", **a}, {"id": b["id"], "platform": "android", **b}]
    manifest = {"format": 1, "source": source_hash()}
    if picks.get("sting"):
        s = picks["sting"]
        manifest["sting"] = {"file": "sting.m4a", "dur": s["dur"], "voiceAt": s["voiceAt"], "voiceEnd": s["voiceEnd"],
                             "text": s["text"]}
    manifest["earcons"] = {name: {"file": f"earcons/{name}.wav", "dur": SHAPES[name][2]} for name in EARCONS}
    manifest["welcome"] = welcome["ios"]
    manifest["help"] = help_
    if put(MANIFEST, (json.dumps(manifest, indent=1, ensure_ascii=False) + "\n").encode("utf-8")):
        wrote.append("app.json")

    # What nothing plays any more: old clips, earcon copies no text uses, a sting that isn't picked. Nothing else
    # in content/app/ (the licences) is this tool's to remove.
    keep = {s["play"] for e in [manifest["welcome"], *help_] for s in e["steps"] if "play" in s}
    removed = []
    for f in sorted((OUT / "tts").glob("*")):
        if f.is_file() and f"tts/{f.stem}" not in keep:
            f.unlink()
            removed.append(f"tts/{f.name}")
    for f in sorted((OUT / "earcons").glob("*")):
        if f.is_file() and f.name not in {f"{n}.wav" for n in EARCONS} and f"earcons/{f.stem}" not in keep:
            f.unlink()
            removed.append(f"earcons/{f.name}")
    if not picks.get("sting") and (OUT / "sting.m4a").exists():
        (OUT / "sting.m4a").unlink()
        removed.append("sting.m4a")
    return manifest, wrote, removed


def spoken_seconds(entry):
    return sum(s.get("dur", 0) if "play" in s else s.get("pause", 0) for s in entry["steps"])


def report(manifest):
    """The topics' spoken lengths, warnings for any out of range, and what content/app/ weighs."""
    warn = []
    for e in [manifest["welcome"], *manifest["help"]]:
        kind = "help" if "id" in e else "welcome"
        secs = spoken_seconds(e)
        lo, hi = SPOKEN[kind]
        name = e.get("id", "welcome") + (f" ({e['platform']})" if e.get("platform") else "")
        line = f"  {name}: {sum(1 for s in e['steps'] if 'play' in s)} clips, {secs:.1f} s"
        if not lo <= secs <= hi:
            warn.append(f"{name}: {secs:.1f} s spoken ({lo} to {hi})")
            line += "  !"
        print(line)
    files = [f for f in OUT.rglob("*") if f.is_file() and "licences" not in f.relative_to(OUT).parts]
    size = sum(f.stat().st_size for f in files)
    by = Counter()
    for f in files:
        by[f.relative_to(OUT).parts[0] if len(f.relative_to(OUT).parts) > 1 else f.name] += f.stat().st_size
    print(f"content/app: {len(files)} files, {size / 1e6:.2f} MB (" +
          ", ".join(f"{k} {v / 1e3:.0f} KB" for k, v in sorted(by.items())) + "; the licences aren't counted)")
    return warn


# ----- Check -----

def check(audio=True):
    """Whether content/app/ is what app_text.toml and the picks make: (a summary line, errors, warnings). Reads
    only; never calls ElevenLabs. With audio, every file app.json names is opened and its length checked."""
    errors, warnings = [], []
    if tomllib is None:
        # A Python too old to read TOML: app.json's source hash (of the text's bytes) still says whether it was built
        # from this text and these picks, and every file is checked; only the paragraph-by-paragraph comparison waits.
        doc, problems = {}, []
        warnings.append(f"{rel(TEXT)} not read (Python 3.11 or later reads it): app.json was checked against its "
                        "source hash, not paragraph by paragraph")
    else:
        doc, problems = read_text()
    errors += [f"{rel(TEXT)}: {p}" for p in problems]
    if not MANIFEST.exists():
        return ("app: no content/app/app.json",
                errors + ["no content/app/app.json: run py -3.13 tools/app_audio.py build"], warnings)
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except ValueError as e:
        return "app: app.json doesn't parse", errors + [f"app.json: {e}"], warnings
    picks = load_picks()
    stale = manifest.get("source") != source_hash()
    if stale:
        errors.append("app.json is out of date with tools/app_text.toml or the picks: run "
                      "py -3.13 tools/app_audio.py build")
    if manifest.get("format") != 1:
        errors.append(f"app.json format {manifest.get('format')!r}, expected 1")
    family = picks.get("earcons", DEFAULT_FAMILY)
    if family not in FAMILIES:
        errors.append(f"picks: no earcon family {family!r}")
        family = DEFAULT_FAMILY
    # The text, as the apps will show it, against the source (the clips' own details need a build to know).
    if tomllib and not problems and not stale:
        per = {p: entries(doc, p, []) for p in PLATFORMS}
        want = [("welcome", None, per["ios"][0])]
        for ios, android in zip(per["ios"][1:], per["android"][1:]):
            same = (ios.title, ios.summary, ios.items, ios.links) == (android.title, android.summary, android.items,
                                                                     android.links)
            want += [(ios.id, None, ios)] if same else [(ios.id, "ios", ios), (android.id, "android", android)]
        got = [("welcome", None, manifest.get("welcome") or {})] + [(h.get("id"), h.get("platform"), h)
                                                                   for h in manifest.get("help") or []]
        if [(w[0], w[1]) for w in want] != [(g[0], g[1]) for g in got]:
            errors.append("app.json's topics aren't the text's: run build")
        else:
            for (tid, platform, e), (_, _, m) in zip(want, got):
                errors += _check_entry(e, m, f"{tid}{f' ({platform})' if platform else ''}")
    # Every file it names, there and as long as it says.
    steps = [s for e in [manifest.get("welcome") or {}, *(manifest.get("help") or [])] for s in e.get("steps", [])]
    plays = {s["play"]: s.get("dur") for s in steps if "play" in s}

    def file_problem(item):
        path, dur = item
        f = next((OUT / f"{path}{ext}" for ext in (".m4a", ".mp3", ".opus") if (OUT / f"{path}{ext}").exists()), None)
        if f is None:
            return f"{path}: no audio file in content/app/"
        if audio and isinstance(dur, (int, float)) and abs(duration(f) - dur) > 0.12:
            return f"{path}: app.json says {dur} s, {f.name} is {duration(f):.2f} s"
        return None
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        errors += [p for p in pool.map(file_problem, sorted(plays.items())) if p]
    if (OUT / "tts").exists():
        for f in sorted((OUT / "tts").glob("*")):
            if f"tts/{f.stem}" not in plays:
                errors.append(f"tts/{f.name}: nothing plays it (build removes it)")
    for name, data in synth(family).items():
        f = OUT / "earcons" / f"{name}.wav"
        if not f.exists():
            errors.append(f"earcons/{name}.wav: missing (build or pick earcons makes it)")
        elif f.read_bytes() != data:
            have, want_ = wav_samples(f.read_bytes()), wav_samples(data)
            if len(have) != len(want_) or max(abs(a - b) for a, b in zip(have, want_)) > 1:
                errors.append(f"earcons/{name}.wav isn't the {family} family's: run py -3.13 tools/app_audio.py "
                              f"pick earcons {family}")
            else:
                warnings.append(f"earcons/{name}.wav differs from this machine's synthesis by 1 LSB at most")
        if (manifest.get("earcons") or {}).get(name) != {"file": f"earcons/{name}.wav", "dur": SHAPES[name][2]}:
            errors.append(f"app.json's earcon {name} isn't earcons/{name}.wav, {SHAPES[name][2]} s")
    sting = picks.get("sting")
    if sting:
        f = OUT / "sting.m4a"
        if not f.exists():
            errors.append("sting.m4a: picked but missing (pick sting makes it)")
        elif hashlib.sha256(f.read_bytes()).hexdigest() != sting.get("sha256"):
            errors.append(f"sting.m4a isn't the picked mix: run py -3.13 tools/app_audio.py pick sting "
                          f"{sting.get('voice')} {sting.get('bed')}")
        want_sting = {"file": "sting.m4a", "dur": sting.get("dur"), "voiceAt": sting.get("voiceAt"),
                      "voiceEnd": sting.get("voiceEnd"), "text": sting.get("text")}
        if manifest.get("sting") != want_sting:
            errors.append("app.json's sting isn't the picked one: run build")
    elif "sting" in manifest:
        errors.append("app.json has a sting, but none is picked")
    for e in [manifest.get("welcome") or {}, *(manifest.get("help") or [])]:
        kind = "help" if "id" in e else "welcome"
        secs, (lo, hi) = spoken_seconds(e), SPOKEN[kind]
        if not lo <= secs <= hi:
            warnings.append(f"{e.get('id', 'welcome')}{' (' + e['platform'] + ')' if e.get('platform') else ''}: "
                            f"{secs:.1f} s spoken ({lo} to {hi})")
    others = [f for f in OUT.glob("*") if f.name not in {"app.json", "sting.m4a", "tts", "earcons", "licences"}]
    for f in others:
        warnings.append(f"content/app/{f.name}: not made by tools/app_audio.py (the apps bundle it anyway)")
    files = [f for f in OUT.rglob("*") if f.is_file() and "licences" not in f.relative_to(OUT).parts]
    secs = sum(spoken_seconds(e) for e in [manifest.get("welcome") or {}, *(manifest.get("help") or [])])
    topics = len({h.get("id") for h in manifest.get("help") or []})
    summary = (f"app: welcome and {topics} help topics ({len(manifest.get('help') or [])} entries), {len(plays)} "
               f"clips, {secs / 60:.1f} min, sting {'picked' if sting else 'not picked'}, earcons {family}, "
               f"{sum(f.stat().st_size for f in files) / 1e6:.1f} MB")
    return summary, errors, warnings


def _check_entry(e, m, where):
    """One entry of app.json against its source: the text, titles, links, and a clip per paragraph in order."""
    errors = []
    paras = [x for x in e.items if isinstance(x, Para)]
    if m.get("title") != e.title or (e.kind == "help" and m.get("summary") != e.summary):
        errors.append(f"{where}: the title or summary isn't the text's")
    if m.get("text") != [p.text for p in paras]:
        errors.append(f"{where}: the paragraphs aren't the text's")
    if e.kind == "help" and m.get("links") != e.links:
        errors.append(f"{where}: the links aren't the text's")
    plays = [s for s in m.get("steps", []) if "play" in s]
    if len(plays) != len(e.items) or len(m.get("clipParagraph", [])) != len(plays):
        return errors + [f"{where}: {len(plays)} clips for {len(e.items)} paragraphs and sounds"]
    k = 0
    for x, s, cp in zip(e.items, plays, m["clipParagraph"]):
        if isinstance(x, Cue):
            if s["play"] != f"earcons/{x.name}-demo" or cp != -1 or not s.get("sfx"):
                errors.append(f"{where}: the {x.name} sound isn't where the text has it")
        else:
            lines = s.get("lines") or [{}]
            if cp != k or lines[0].get("text") != x.text or not s["play"].startswith(f"tts/{slug(x.text)}-"):
                errors.append(f"{where}: paragraph {k + 1}'s clip isn't its own")
            elif lines[0].get("at", -1) < 0 or lines[0]["at"] + lines[0].get("len", 0) > s.get("dur", 0) + 0.05:
                errors.append(f"{where}: paragraph {k + 1}'s line doesn't fit in its clip")
            k += 1
    return errors


# ----- Command line -----

def main():
    sys.stdout.reconfigure(errors="replace")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    au = sub.add_parser("audition", help="make the variants to listen to: tools/cache/app/audition/index.html")
    au_sub = au.add_subparsers(dest="what", required=True)
    a_st = au_sub.add_parser("sting", help="voice takes over logo beds")
    a_st.add_argument("--takes", type=int, default=2, help="takes of each bed style (default 2)")
    a_st.add_argument("--music", action="store_true", help="also ElevenLabs music beds in the same styles")
    one = a_st.add_mutually_exclusive_group()
    one.add_argument("--voice", help="mix this voice take with every bed (the default is jessica-a1 and don-a1)")
    one.add_argument("--bed", help="mix every voice take with this bed")
    a_ea = au_sub.add_parser("earcons", help="every earcon family, in a game and over a Bluetooth headset")
    a_ea.add_argument("--elevenlabs", action="store_true", help="also ElevenLabs takes, to compare (not pickable)")
    pk = sub.add_parser("pick", help="the owner's pick, into content/app/ and tools/app_audio_picks.json")
    pk_sub = pk.add_subparsers(dest="what", required=True)
    p_st = pk_sub.add_parser("sting")
    p_st.add_argument("voice")
    p_st.add_argument("bed")
    p_st.add_argument("--at", type=float, help="when the voice starts (s)")
    p_st.add_argument("--duck", type=float, default=DUCK_DB, help=f"how far the bed ducks under the voice (dB, "
                                                                  f"default {DUCK_DB:g})")
    p_st.add_argument("--length", type=float, help="the sting's length (s)")
    p_ea = pk_sub.add_parser("earcons")
    p_ea.add_argument("family", choices=FAMILIES)
    bd = sub.add_parser("build", help="the welcome and help clips, and app.json")
    bd.add_argument("--no-api", action="store_true", help="never call ElevenLabs: a line not in the cache is an error")
    bd.add_argument("--force", action="store_true", help="encode every clip again from the cache (no new speech)")
    sub.add_parser("check", help="exit 1 if content/app/ isn't what the text and the picks make")
    args = ap.parse_args()

    if args.cmd == "check":
        summary, errors, warnings = check()
        print(f"{summary}: {'OK' if not errors else f'{len(errors)} errors'}")
        for e in errors:
            print(f"  x {e}")
        for w in warnings:
            print(f"  ! {w}")
        sys.exit(1 if errors else 0)

    api = Api(allowed=not getattr(args, "no_api", False))
    paying = api.allowed and (args.cmd == "build" or args.what == "sting" or getattr(args, "elevenlabs", False))
    start = balance() if paying else None
    try:
        if args.cmd == "audition" and args.what == "sting":
            audition_sting(args.takes, args.music, args.voice, args.bed)
        elif args.cmd == "audition":
            audition_earcons(args.elevenlabs)
        elif args.cmd == "pick" and args.what == "sting":
            pick_sting(args.voice, args.bed, args.at, args.duck, args.length)
            _rebuild(api)
        elif args.cmd == "pick":
            pick_earcons(args.family)
            _rebuild(api)
        elif args.cmd == "build":
            manifest, wrote, removed = build(force=args.force)
            print(f"wrote {len(wrote)} files" + (": " + ", ".join(wrote) if 0 < len(wrote) <= 12 else "")
                  + (f"; removed {len(removed)}: {', '.join(removed)}" if removed else ""))
            for w in report(manifest):
                print(f"  ! {w}")
    except CacheMiss as e:
        raise SystemExit(f"x {e}")
    finally:
        if api.calls:
            # The account's count catches up some seconds after the requests (sometimes minutes): wait a little for
            # it to move, then for it to settle.
            end, waited = balance(), 0
            while start and end and end[0] == start[0] and waited < 30:
                time.sleep(5)
                waited += 5
                end = balance()
            for _ in range(3):
                time.sleep(4)
                now = balance()
                if now == end:
                    break
                end = now
            if start and end and end[0] != start[0]:
                print(f"ElevenLabs: {api.calls} requests, {end[0] - start[0]:,} credits used so far "
                      f"({end[1] - end[0]:,} left this period)")
            else:
                print(f"ElevenLabs: {api.calls} requests (the account's count hasn't caught up with them yet)")


def _rebuild(api):
    """After a pick: app.json again, from the cache only (a pick never pays for speech)."""
    if not MANIFEST.exists():
        print("now run: py -3.13 tools/app_audio.py build")
        return
    allowed, api.allowed = api.allowed, False
    try:
        manifest, wrote, removed = build()
        print(f"app.json updated: {', '.join(wrote) or 'nothing changed'}")
    except CacheMiss as e:
        print(f"  ! app.json not updated ({e}): run py -3.13 tools/app_audio.py build")
    finally:
        api.allowed = allowed


if __name__ == "__main__":
    main()
