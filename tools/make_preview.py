"""The app preview videos: the App Store's (886x1920, from the iPhone simulator on the Mac) and Play's (1080x1920, from
the emulator, for YouTube, with an .srt of what's said). brand/previews/storyboard.json says what each take records
and the sounds it makes; an edit decision list per store (brand/previews/appstore.json, play.json) cuts the takes
into the 15-30 s preview, with a caption on each scene. The owner approves the cut (gate 5).

  capture-android  takes on the emulator: scrcpy (2.1 or later, if it's installed) records the picture and the
                   sound; without it, adb's screenrecord records the picture, and the sound is put together from
                   content/ (assemble): the sting and the earcons from content/app/, and each turn's clips from its
                   map's steps, placed by the app's EpicShots log lines
  capture-ios      (the Mac) takes on the booted simulator: simctl recordVideo, and the sound through the BlackHole
                   2ch audio device with ffmpeg (Simulator > I/O > Audio Output > BlackHole 2ch, brew install
                   blackhole-2ch). A real iPhone: QuickTime Player > File > New Movie Recording, the iPhone as camera
                   and microphone, then `import`
  import           a recording made some other way, as a take
  assemble         an Android take's sound again, from content/ and its log lines (after changing the storyboard)
  sync             lines a take's sound up with its picture: the intro's first frame (the circle and the wordmark
                   appearing over the splash) against the first sound louder than -40 dBFS (the sting); --offset
                   sets it by hand
  edit             cuts an EDL: trims, scale and crop to the target, 30 fps, captions drawn in Atkinson Hyperlegible
                   Next, the sound at -16 LUFS (two-pass loudnorm, -1 dBTP), H.264 High 4.0 and AAC 256k
  check            a video against the store's rules (ffprobe): size, at most 30 fps and constant, H.264 High up to
                   level 4.0, yuv420p, stereo AAC, picture and sound the same length, 15-30 s, under 500 MB
  plan             the storyboard and the EDLs checked, each take's sounds with their lengths and, once captured,
                   where they fall on its timeline (to choose the EDL's in and out points)

Takes live in build/preview/takes/<android|ios>/<take>/ (video, sound.wav, events.jsonl, take.json, sync.json); a
cut in build/preview/<target>/. An EDL's in and out are seconds from the take's zero: the intro's first frame, or for
a take without the intro the app's first frame. The App Store cut is 01_IPHONE_67.mp4 (deliver reads the iPhone size
from the name): edit --install copies it to ios/fastlane/app_previews/en-US/. The App Store's must show the iPhone app
(its source is ios); Play's comes from the emulator.

Usage (from the repo root; py -3.13 here, python3 on the Mac):
  py -3.13 tools/make_preview.py plan
  py -3.13 tools/make_preview.py capture-android                  every take (or --takes main,settings)
  py -3.13 tools/make_preview.py edit brand/previews/play.json    -> build/preview/play/epic-audio-games-preview.mp4
  py -3.13 tools/make_preview.py check build/preview/play/epic-audio-games-preview.mp4
  python3 tools/make_preview.py capture-ios                       (the Mac, the simulator booted)
  python3 tools/make_preview.py edit brand/previews/appstore.json --install
Needs ffmpeg and ffprobe; assemble, sync and edit need numpy and Pillow (and fontTools, for the captions).
"""
import argparse
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import wave
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

PREVIEWS = ROOT / "brand" / "previews"
STORYBOARD = PREVIEWS / "storyboard.json"
CONTENT = ROOT / "content"
GAMES = ROOT / "games"
BUILD = ROOT / "build" / "preview"
TAKES = BUILD / "takes"
FPS = 30
RATE = 48000
LOG_TAG = "EpicShots"
NAVY = (11, 20, 48)           # the splash and the intro (docs/DESIGN.md's Dark background)
SURFACE = (22, 39, 94)        # the intro's circle (Dark surface)
INSTALL = {"appstore": ROOT / "ios" / "fastlane" / "app_previews" / "en-US"}

TARGETS = {
    "appstore": {"size": (886, 1920), "seconds": (15.0, 30.0), "strict": True, "srt": False,
                 "about": "the App Store's app preview (every iPhone size group takes 886x1920)"},
    "play": {"size": (1080, 1920), "seconds": (15.0, 30.0), "strict": False, "srt": True,
             "about": "Play's promo video, on YouTube (portrait is fine; no black bars)"},
}
VIDEO_CODEC = ["-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p", "-r", str(FPS),
               "-b:v", "10M", "-maxrate", "12M", "-bufsize", "20M"]
AUDIO_CODEC = ["-c:a", "aac", "-b:a", "256k", "-ar", str(RATE), "-ac", "2"]
LOUDNESS = {"I": -16.0, "TP": -1.0, "LRA": 11.0}
# Apple's guideline 2.3.10: no other platform in App Store metadata. Play: no promotional words on store images.
APPLE_WORDS = re.compile(r"\b(android|talkback|google|play store)\b", re.I)
PROMO_WORDS = re.compile(r"(#1\b|\b(free|best|top|new|sale|download now|install now)\b)", re.I)


class PreviewError(Exception):
    pass


# ----- Small things -----

def rel(path):
    path = Path(path).resolve()
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def read_json(path, what=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise PreviewError(f"{rel(path)} isn't there" + (f" ({what})" if what else ""))
    except ValueError as e:
        raise PreviewError(f"{rel(path)}: {e}")


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    os.replace(tmp, path)


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def plain_caption(marked):
    """A caption's words without the stars, with typographic apostrophes (as drawn)."""
    text = re.sub(r"(\w)'(\w)", "\\1\u2019\\2", marked.replace("*", ""))
    return re.sub(r"\s+", " ", text.replace("'", "\u2019")).strip()


def need(tool):
    if shutil.which(tool) is None:
        raise PreviewError(f"{tool} isn't on PATH (ffmpeg 7: winget install Gyan.FFmpeg, or brew install ffmpeg)")


def ffmpeg(*args, what="ffmpeg"):
    need("ffmpeg")
    cmd = ["ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "error", *[str(a) for a in args]]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        tail = "\n".join(p.stderr.strip().splitlines()[-8:])
        raise PreviewError(f"{what} failed:\n{tail}")
    return p


def ffprobe(path):
    need("ffprobe")
    p = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise PreviewError(f"ffprobe can't read {rel(path)}: {p.stderr.strip()[-300:]}")
    return json.loads(p.stdout)


def media_seconds(path):
    info = ffprobe(path)
    return float(info.get("format", {}).get("duration") or 0)


def decode_audio(path, channels=2, stream="a:0"):
    """A file's sound as float32 samples at 48 kHz: (n, channels). A mono file comes out at full level in both
    channels, as a phone plays it (ffmpeg's own upmix would take 3 dB off each)."""
    import numpy as np
    need("ffmpeg")
    info = ffprobe(path)
    audio = [s for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    if not audio:
        raise PreviewError(f"{rel(path)} has no sound")
    mono = int(audio[0].get("channels") or 2) == 1
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-i", str(path), "-map",
                        f"0:{stream}", "-vn", "-f", "f32le", "-ac", "1" if mono or channels == 1 else str(channels),
                        "-ar", str(RATE), "-"], capture_output=True)
    if p.returncode != 0:
        raise PreviewError(f"ffmpeg can't decode the sound of {rel(path)}: "
                           f"{p.stderr.decode('utf-8', 'replace').strip()[-300:]}")
    samples = np.frombuffer(p.stdout, dtype=np.float32)
    if mono and channels > 1:
        return np.repeat(samples.reshape(-1, 1), channels, axis=1)
    return samples.reshape(-1, channels)


def write_wav(path, samples):
    """float samples (n, 2) in -1..1 as 16-bit PCM stereo at 48 kHz."""
    import numpy as np
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).round().astype("<i2")
    tmp = path.with_name(path.name + ".tmp")
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(samples.shape[1])
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    os.replace(tmp, path)


# ----- The storyboard and the EDLs -----

def load_storyboard(path=STORYBOARD):
    sb = read_json(path, "the preview's storyboard")
    problems = check_storyboard(sb)
    if problems:
        raise PreviewError(f"{rel(path)}:\n  " + "\n  ".join(problems))
    return sb


def check_storyboard(sb):
    out = []
    for key in ("game", "scenes", "takes"):
        if key not in sb:
            out.append(f"no {key}")
    if out:
        return out
    ids = [s.get("id") for s in sb["scenes"]]
    if len(ids) != len(set(ids)) or not all(ids):
        out.append("every scene needs an id of its own")
    for s in sb["scenes"]:
        if s.get("caption") and s["caption"].count("*") % 2:
            out.append(f"scene {s.get('id')}: the caption has an odd number of stars")
    if not (GAMES / sb["game"] / "map.json").exists():
        out.append(f"game {sb['game']}: games/{sb['game']}/map.json isn't there")
    for name, take in sb["takes"].items():
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            out.append(f"take {name}: names are letters, digits, _ and -")
        if not isinstance(take.get("seconds"), (int, float)) or not 3 <= take["seconds"] <= 170:
            out.append(f"take {name}: seconds is 3 to 170 (screenrecord stops at 180)")
        for cue in take.get("sound", []):
            kinds = [k for k in ("sting", "earcon", "turn", "clip") if k in cue]
            if len(kinds) != 1:
                out.append(f"take {name}: a sound is one of sting, earcon, turn or clip: {cue}")
            if not cue.get("at") and not cue.get("end"):
                out.append(f"take {name}: a sound needs at or end (where it goes): {cue}")
            for anchor in as_list(cue.get("at")) + as_list(cue.get("end")):
                if isinstance(anchor, dict) and "line" in anchor:
                    try:
                        re.compile(anchor["line"])
                    except re.error as e:
                        out.append(f"take {name}: {anchor['line']!r} isn't a regular expression ({e})")
                elif not isinstance(anchor, (int, float)) and not (isinstance(anchor, dict) and
                                                                    ("t" in anchor or "event" in anchor)):
                    out.append(f"take {name}: an anchor is a number, or has line, event or t: {anchor}")
    return out


def load_edl(path, sb):
    edl = read_json(path, "an edit decision list")
    errors, warnings = check_edl(edl, sb)
    for w in warnings:
        print(f"  warning: {w}")
    if errors:
        raise PreviewError(f"{rel(path)}:\n  " + "\n  ".join(errors))
    return edl


def clip_caption(edl, sb, clip):
    if "caption" in clip:
        return clip["caption"]
    scene = next((s for s in sb["scenes"] if s["id"] == clip.get("scene")), None)
    return scene.get("caption") if scene else None


def check_edl(edl, sb):
    errors, warnings = [], []
    target = edl.get("target")
    if target not in TARGETS:
        return [f"target is one of {', '.join(TARGETS)}"], []
    if edl.get("source") not in ("android", "ios"):
        errors.append("source is android or ios (whose takes it cuts)")
    if target == "appstore" and edl.get("source") != "ios":
        warnings.append("an App Store preview has to show the iPhone app: its source should be ios")
    if not edl.get("clips"):
        errors.append("no clips")
        return errors, warnings
    total = 0.0
    scene_ids = {s["id"] for s in sb["scenes"]}
    for i, clip in enumerate(edl["clips"]):
        where = f"clips[{i}]"
        if clip.get("take") not in sb["takes"]:
            errors.append(f"{where}: take {clip.get('take')} isn't in the storyboard")
        if "scene" in clip and clip["scene"] not in scene_ids:
            errors.append(f"{where}: scene {clip['scene']} isn't in the storyboard")
        if not isinstance(clip.get("in"), (int, float)) or not isinstance(clip.get("out"), (int, float)) or \
                clip["out"] <= clip["in"] or clip["in"] < -1:
            errors.append(f"{where}: in and out are seconds from the take's zero, out after in")
            continue
        sound = clip.get("sound")
        if sound and sound.get("take") not in sb["takes"]:
            errors.append(f"{where}: sound.take {sound.get('take')} isn't in the storyboard")
        total += round((clip["out"] - clip["in"]) * FPS) / FPS
        caption = clip_caption(edl, sb, clip)
        if caption:
            if caption.count("*") % 2:
                errors.append(f"{where}: the caption has an odd number of stars")
            if target == "appstore" and APPLE_WORDS.search(caption):
                errors.append(f"{where}: {caption!r} names another platform (App Store guideline 2.3.10)")
            if PROMO_WORDS.search(caption):
                warnings.append(f"{where}: {caption!r} has a promotional word the stores frown on")
    low, high = TARGETS[target]["seconds"]
    if not low <= total <= high:
        (errors if TARGETS[target]["strict"] else warnings).append(
            f"the clips add up to {total:.2f} s; {target} wants {low:.0f} to {high:.0f}")
    return errors, warnings


# ----- Conditions and turns (docs/MAP_FORMAT.md) -----

_TOKEN = re.compile(r'\s*(?:(\d+(?:\.\d+)?)|("(?:[^"\\]|\\.)*")|([A-Za-z_][A-Za-z0-9_]*)|'
                    r'(&&|\|\||==|!=|<=|>=|[-+*/%()<>!?:,]))')


def truthy(v):
    if isinstance(v, str):
        return v != ""
    return bool(v)


def number(v):
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


class Expr:
    """The maps' small expressions (`tries >= 2 && !nana`, `a ? b : c`, max/min/floor), on known variables."""

    def __init__(self, text, variables):
        self.text, self.vars, self.toks, pos = text, variables, [], 0
        while pos < len(text):
            m = _TOKEN.match(text, pos)
            if not m or m.end() == pos:
                if text[pos:].strip() == "":
                    break
                raise PreviewError(f"can't read the condition {text!r}")
            pos = m.end()
            num, string, ident, op = m.groups()
            self.toks.append(("n", float(num)) if num else ("s", json.loads(string)) if string else
                             ("i", ident) if ident else ("o", op))
        self.i = 0

    def value(self):
        v = self.ternary()
        if self.i != len(self.toks):
            raise PreviewError(f"can't read the condition {self.text!r}")
        return v

    def peek(self):
        return self.toks[self.i][1] if self.i < len(self.toks) and self.toks[self.i][0] == "o" else None

    def take(self, op=None):
        if op and self.peek() != op:
            raise PreviewError(f"can't read the condition {self.text!r} (expected {op})")
        self.i += 1

    def ternary(self):
        cond = self.either()
        if self.peek() == "?":
            self.take()
            a = self.ternary()
            self.take(":")
            b = self.ternary()
            return a if truthy(cond) else b
        return cond

    def either(self):
        v = self.both()
        while self.peek() == "||":
            self.take()
            r = self.both()
            v = truthy(v) or truthy(r)
        return v

    def both(self):
        v = self.compare()
        while self.peek() == "&&":
            self.take()
            r = self.compare()
            v = truthy(v) and truthy(r)
        return v

    def compare(self):
        a = self.sum()
        while self.peek() in ("==", "!=", "<", "<=", ">", ">="):
            op = self.peek()
            self.take()
            b = self.sum()
            if op in ("==", "!="):
                same = (a == b) if isinstance(a, str) and isinstance(b, str) else \
                    (str(a) == str(b) if isinstance(a, str) or isinstance(b, str) else number(a) == number(b))
                a = same if op == "==" else not same
            else:
                x, y = number(a), number(b)
                a = {"<": x < y, "<=": x <= y, ">": x > y, ">=": x >= y}[op]
        return a

    def sum(self):
        a = self.product()
        while self.peek() in ("+", "-"):
            op = self.peek()
            self.take()
            b = self.product()
            a = number(a) + number(b) if op == "+" else number(a) - number(b)
        return a

    def product(self):
        a = self.unary()
        while self.peek() in ("*", "/", "%"):
            op = self.peek()
            self.take()
            b = number(self.unary())
            x = number(a)
            a = x * b if op == "*" else (x / b if b else 0.0) if op == "/" else (math.fmod(x, b) if b else 0.0)
        return a

    def unary(self):
        if self.peek() == "!":
            self.take()
            return not truthy(self.unary())
        if self.peek() == "-":
            self.take()
            return -number(self.unary())
        return self.atom()

    def atom(self):
        if self.i >= len(self.toks):
            raise PreviewError(f"can't read the condition {self.text!r}")
        kind, v = self.toks[self.i]
        if kind == "o" and v == "(":
            self.take()
            r = self.ternary()
            self.take(")")
            return r
        self.i += 1
        if kind in ("n", "s"):
            return v
        if kind == "i":
            if v in ("true", "false"):
                return v == "true"
            if self.peek() == "(":
                self.take()
                args = [self.ternary()]
                while self.peek() == ",":
                    self.take()
                    args.append(self.ternary())
                self.take(")")
                nums = [number(a) for a in args]
                if v == "max":
                    return max(nums)
                if v == "min":
                    return min(nums)
                if v == "floor":
                    return float(math.floor(nums[0]))
                if v == "rand":
                    return nums[0]       # the low end: a preview can't know the draw
                raise PreviewError(f"{v}() isn't a function the maps have ({self.text!r})")
            return self.vars.get(v, 0)
        raise PreviewError(f"can't read the condition {self.text!r}")


def evaluate(text, variables):
    return Expr(str(text), variables).value()


def case_key(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def apply_set(changes, variables, notes):
    for name, value in (changes or {}).items():
        if isinstance(value, str) and re.fullmatch(r"[+-]\d+(\.\d+)?", value):
            variables[name] = number(variables.get(name, 0)) + float(value)
        elif isinstance(value, str) and value.startswith("="):
            variables[name] = evaluate(value[1:], variables)
        elif isinstance(value, str) and value.startswith("rand("):
            variables[name] = evaluate(value, variables)
            notes.append(f"{name} = {value}: taken as its lowest value")
        else:
            variables[name] = value


_maps = {}


def game_map(game):
    if game not in _maps:
        _maps[game] = read_json(GAMES / game / "map.json", f"the {game} map")
    return _maps[game]


def content_file(game, path):
    """A clip of the map (no extension) in content/<game>/: whichever of .m4a, .mp3, .opus is there."""
    for ext in (".m4a", ".mp3", ".opus", ".ogg", ".wav"):
        p = CONTENT / game / (path + ext)
        if p.exists():
            return p
    raise PreviewError(f"content/{game}/{path} isn't there (.m4a, .mp3 or .opus): a pack's clip, or content/ missing")


def who_name(game, key):
    """How the transcript names a speaker: nobody for the narrator (docs/DESIGN.md)."""
    if not key or key.upper() in ("NARRATOR", "HOST"):
        return None
    return game_map(game).get("who", {}).get(key, key.title())


def turn_sounds(game, nodes, variables=None, picks=None, follow=True):
    """What the app plays for these nodes' say, one after another (and on through plain `go`s): sounds as
    {at, kind, file, dur, volume, lines}, the length, and notes on anything a preview can't know."""
    m = game_map(game)
    state = dict(m.get("vars", {}))
    state.update(variables or {})
    picks = list(picks or [])
    sounds, beds, notes = [], [], []
    t = 0.0

    def run(steps):
        nonlocal t
        for step in steps:
            if "when" in step and not truthy(evaluate(step["when"], state)):
                continue
            if "play" in step:
                lines = [dict(line, who=who_name(game, line.get("who"))) for line in step.get("lines", [])]
                sounds.append({"at": t, "kind": "sfx" if step.get("sfx") else "clip",
                               "file": content_file(game, step["play"]), "dur": float(step["dur"]), "volume": 1.0,
                               "lines": lines, "name": f"{game}/{step['play']}"})
                t += float(step["dur"])
            elif "pause" in step:
                t += float(step["pause"])
            elif "bed" in step:
                if step["bed"] is None:
                    for b in beds:
                        b["stop"] = t if b["stop"] is None else b["stop"]
                elif not any(b["path"] == step["bed"] and b["stop"] is None for b in beds):
                    beds.append({"path": step["bed"], "at": t, "file": content_file(game, step["bed"]),
                                 "dur": float(step.get("dur") or 0), "volume": float(step.get("volume", 1.0)),
                                 "stop": None})
            elif "pick" in step:
                choice = picks.pop(0) if picks else 0
                if len(step["pick"]) > 1 and not notes.count("pick"):
                    notes.append(f"a pick of {len(step['pick'])}: took {choice} (the app draws at random; "
                                 f"\"picks\" chooses)")
                run(step["pick"][choice])
            elif "by" in step:
                key = case_key(state.get(step["by"], 0))
                run(step.get("cases", {}).get(key, step.get("else", [])))
            elif "num" in step:
                notes.append(f"{step['num']} is read out with number clips: left out")

    queue = list(nodes)
    visited = 0
    while queue:
        nid = queue.pop(0)
        node = m["nodes"].get(nid)
        if node is None:
            raise PreviewError(f"{nid} isn't a node of games/{game}/map.json")
        apply_set(node.get("set"), state, notes)
        run(node.get("say", []))
        visited += 1
        if follow and not queue and isinstance(node.get("go"), str) and visited < 20 and not node.get("ask"):
            queue.append(node["go"])
    end = t
    for b in beds:
        stop = b["stop"] if b["stop"] is not None else end
        if b["dur"]:
            stop = min(stop, b["at"] + b["dur"])
        sounds.append({"at": b["at"], "kind": "bed", "file": b["file"], "dur": max(0.0, stop - b["at"]),
                       "volume": b["volume"], "lines": [], "name": f"{game}/{b['path']}"})
    return sounds, end, notes


def app_manifest():
    return read_json(CONTENT / "app" / "app.json", "content/app/app.json (tools/app_audio.py build)")


def cue_sounds(cue, game):
    """A storyboard sound: (sounds from its start, length, notes, a name)."""
    if cue.get("sting"):
        sting = app_manifest()["sting"]
        f = CONTENT / "app" / sting["file"]
        line = {"at": sting.get("voiceAt", 0.0), "len": sting.get("voiceEnd", sting["dur"]) - sting.get("voiceAt", 0.0),
                "who": None, "text": sting.get("text", ""), "sound": "Music"}
        return ([{"at": 0.0, "kind": "sting", "file": f, "dur": float(sting["dur"]), "volume": float(cue.get(
            "volume", 1.0)), "lines": [line], "name": "app/sting"}], float(sting["dur"]), [], "the sting")
    if cue.get("earcon"):
        earcon = app_manifest()["earcons"].get(cue["earcon"])
        if earcon is None:
            raise PreviewError(f"content/app/app.json has no earcon {cue['earcon']!r}")
        f = CONTENT / "app" / earcon["file"]
        return ([{"at": 0.0, "kind": "earcon", "file": f, "dur": float(earcon["dur"]), "volume": float(cue.get(
            "volume", 1.0)), "lines": [], "name": f"app/{earcon['file']}"}], float(earcon["dur"]), [],
                f"the {cue['earcon']} sound")
    if cue.get("turn"):
        g = cue.get("game", game)
        sounds, length, notes = turn_sounds(g, as_list(cue["turn"]), cue.get("vars"), cue.get("picks"),
                                            cue.get("follow", True))
        for s in sounds:
            s["volume"] *= float(cue.get("volume", 1.0))
        return sounds, length, notes, f"{g} {' > '.join(as_list(cue['turn']))}"
    if cue.get("clip"):
        f = CONTENT / cue["clip"]
        if not f.exists():
            raise PreviewError(f"content/{cue['clip']} isn't there")
        d = media_seconds(f)
        return ([{"at": 0.0, "kind": "clip", "file": f, "dur": d, "volume": float(cue.get("volume", 1.0)),
                  "lines": cue.get("lines", []), "name": cue["clip"]}], d, [], cue["clip"])
    raise PreviewError(f"a sound is one of sting, earcon, turn or clip: {cue}")


def describe_anchor(anchor):
    if isinstance(anchor, (int, float)):
        return f"{anchor} s"
    plus = f" {anchor['plus']:+g} s" if anchor.get("plus") else ""
    nth = f" (number {anchor['nth']})" if anchor.get("nth", 1) != 1 else ""
    if "line" in anchor:
        return f"the {anchor.get('tag', LOG_TAG)} line /{anchor['line']}/{nth}{plus}"
    if "event" in anchor:
        return f"the {anchor['event']} event{nth}{plus}"
    return f"{anchor['t']} s{plus}"


def resolve_anchor(anchor, events):
    """An anchor's time on a take's sound timeline (seconds from the recording's start), or None."""
    if isinstance(anchor, (int, float)):
        return float(anchor)
    plus = float(anchor.get("plus", 0.0))
    if "t" in anchor:
        return float(anchor["t"]) + plus
    if "event" in anchor:
        found = [e for e in events if e.get("event") == anchor["event"]]
    else:
        regex = re.compile(anchor["line"])
        tag = anchor.get("tag", LOG_TAG)
        found = [e for e in events if e.get("tag") == tag and regex.search(e.get("msg", ""))]
    nth = int(anchor.get("nth", 1))
    if not found or abs(nth) > len(found) or nth == 0:
        return None
    return found[nth - 1 if nth > 0 else nth]["t"] + plus


def place_sounds(take, events, game):
    """Each of a take's storyboard sounds, placed: [{name, start, dur, how, sounds (at on the take's timeline)}]."""
    placed, notes = [], []
    for cue in take.get("sound", []):
        sounds, length, more, name = cue_sounds(cue, game)
        notes += [f"{name}: {n}" for n in more]
        start, how = None, None
        for anchor in as_list(cue.get("end")):
            t = resolve_anchor(anchor, events)
            if t is not None:
                start, how = t - length, f"ends at {describe_anchor(anchor)}"
                break
        if start is None:
            for anchor in as_list(cue.get("at")):
                t = resolve_anchor(anchor, events)
                if t is not None:
                    start, how = t, f"starts at {describe_anchor(anchor)}"
                    break
        if start is None:
            wanted = [describe_anchor(a) for a in as_list(cue.get("end")) + as_list(cue.get("at"))]
            if cue.get("optional"):
                notes.append(f"{name}: left out (none of {'; '.join(wanted)} happened)")
                continue
            raise PreviewError(f"{name}: none of its anchors happened in the take ({'; '.join(wanted)}); "
                               f"see its events.jsonl, and change the storyboard")
        placed.append({"name": name, "start": start, "dur": length, "how": how,
                       "sounds": [dict(s, at=start + s["at"]) for s in sounds]})
    return placed, notes


# ----- Takes -----

def take_dir(platform, name, takes=None):
    return Path(takes or TAKES) / platform / name


def load_take(platform, name, takes=None):
    folder = take_dir(platform, name, takes)
    info = read_json(folder / "take.json", f"capture the take first: make_preview.py capture-{platform}")
    info["folder"] = folder
    return info


def read_events(folder):
    path = Path(folder) / "events.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def take_video(info):
    return Path(info["folder"]) / info["video"]


def take_sound(info):
    """(file, ffmpeg stream) of a take's sound: its sound.wav, or the video's own sound."""
    if info.get("sound") == "video":
        return take_video(info), "a:0"
    return Path(info["folder"]) / info.get("sound", "sound.wav"), "a:0"


def assemble(platform, name, sb, takes=None):
    """An Android take's sound from content/: the storyboard's sounds placed by its log lines -> sound.wav and
    cues.json."""
    import numpy as np
    info = load_take(platform, name, takes)
    folder = Path(info["folder"])
    events = read_events(folder)
    take = sb["takes"][name]
    placed, notes = place_sounds(take, events, sb["game"])
    seconds = max([info.get("seconds", take["seconds"])] + [p["start"] + p["dur"] + 0.5 for p in placed])
    mix = np.zeros((int(math.ceil(seconds * RATE)) + RATE, 2), dtype=np.float32)
    cache = {}
    for p in placed:
        for s in p["sounds"]:
            if s["file"] not in cache:
                cache[s["file"]] = decode_audio(s["file"])
            audio = cache[s["file"]][:int(round(s["dur"] * RATE))]
            at = int(round(s["at"] * RATE))
            if at < 0:
                audio, at = audio[-at:], 0
            end = min(len(mix), at + len(audio))
            mix[at:end] += audio[:end - at] * s["volume"]
    peak = float(np.max(np.abs(mix))) if len(mix) else 0.0
    if peak > 1.0:
        notes.append(f"the sounds overlap to a peak of {20 * math.log10(peak):+.1f} dBFS: clipped")
    write_wav(folder / "sound.wav", mix)
    write_json(folder / "cues.json", [{"name": p["name"], "start": round(p["start"], 4), "dur": round(p["dur"], 4),
                                       "how": p["how"],
                                       "sounds": [{"at": round(s["at"], 4), "kind": s["kind"], "name": s["name"],
                                                   "dur": round(s["dur"], 4), "volume": s["volume"],
                                                   "lines": s["lines"]} for s in p["sounds"]]}
                                      for p in placed])
    info.update({"sound": "sound.wav", "soundFrom": "assembled"})
    save_take(info)
    print(f"  {rel(folder / 'sound.wav')}: {len(placed)} sound{'s' if len(placed) != 1 else ''} from content/")
    for p in placed:
        print(f"    {p['start']:7.2f} s  {p['name']} ({p['dur']:.2f} s; {p['how']})")
    for n in notes:
        print(f"    note: {n}")
    return placed


def save_take(info):
    data = {k: v for k, v in info.items() if k != "folder"}
    write_json(Path(info["folder"]) / "take.json", data)


# ----- Sync -----

def video_frames(path, seconds=30.0, width=72):
    """The first seconds of a video as small RGB frames at 30 fps: (n, h, w, 3) uint8."""
    import numpy as np
    info = ffprobe(path)
    v = next((s for s in info["streams"] if s.get("codec_type") == "video"), None)
    if v is None:
        raise PreviewError(f"{rel(path)} has no picture")
    w, h = int(v["width"]), int(v["height"])
    rotation = abs(int((v.get("tags") or {}).get("rotate", 0) or 0))
    if rotation in (90, 270):
        w, h = h, w
    height = max(2, int(round(width * h / w / 2)) * 2)
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-i", str(path), "-t",
                        str(seconds), "-an", "-vf", f"fps={FPS},scale={width}:{height}:flags=area", "-f", "rawvideo",
                        "-pix_fmt", "rgb24", "-"], capture_output=True)
    if p.returncode != 0:
        raise PreviewError(f"ffmpeg can't decode {rel(path)}: {p.stderr.decode('utf-8', 'replace')[-300:]}")
    return np.frombuffer(p.stdout, dtype=np.uint8).reshape(-1, height, width, 3)


def find_intro(frames):
    """(the splash's first still frame, the intro's first frame, the app's first frame) as frame numbers, None where
    not found. The intro (docs/DESIGN.md) keeps the splash's navy and emblem and fades in a circle in the surface
    colour round the emblem, and the wordmark: so its first frame is where the middle of the screen starts turning
    from navy to that blue, found where the circle is half there and followed back through the fade's frames. When
    no circle shows up: the first frame that differs from a still, mostly navy screen."""
    import numpy as np
    n = len(frames)
    if n < 4:
        return None, None, None
    f = frames.astype(np.float32)
    h, w = frames.shape[1:3]
    step = np.zeros(n)
    step[1:] = np.abs(f[1:] - f[:-1]).mean(axis=(1, 2, 3))
    first_change = next((i for i in range(1, n) if step[i] > 1.0), None)
    navy = (np.abs(f - np.array(NAVY, dtype=np.float32)).max(axis=3) <= 30).mean(axis=(1, 2))
    x0, x1 = int(w * 0.25), int(w * 0.75)
    half = (x1 - x0) // 2
    centre = f[:, max(0, h // 2 - half):h // 2 + half, x0:x1]
    circle = (np.abs(centre - np.array(SURFACE, dtype=np.float32)).max(axis=3) <= 24).mean(axis=(1, 2))
    centre_step = np.zeros(n)
    centre_step[1:] = np.abs(centre[1:] - centre[:-1]).mean(axis=(1, 2, 3))
    splash = intro = None
    full = next((i for i in range(n) if circle[i] >= 0.2 and navy[i] >= 0.4 and
                 circle[max(0, i - 15):max(0, i - 9)].max(initial=0.0) < 0.05), None)
    if full is not None:
        j = full
        while j > 0 and centre_step[j] > 0.1:
            j -= 1
        intro = j + 1 if j < full else full
        splash = next((i for i in range(intro - 1, -1, -1) if navy[i] < 0.6), -1) + 1
        splash = splash if splash < intro and navy[splash] >= 0.6 else None
    else:
        splash = next((i for i in range(n - 2) if navy[i] >= 0.6 and step[i + 1] < 0.5 and step[i + 2] < 0.5),
                      None)
        if splash is not None:
            quiet = float(max(step[splash + 1], step[splash + 2]))
            threshold = max(0.3, 4 * quiet)
            base = f[splash]
            for j in range(splash + 1, n):
                if np.abs(f[j] - base).mean() > threshold:
                    intro = j
                    while intro - 1 > splash and step[intro - 1] > max(0.05, 2 * quiet):
                        intro -= 1
                    break
    anchor = splash if splash is not None else intro
    launch = first_change if first_change is not None and (anchor is None or first_change <= anchor) else anchor
    return splash, intro, launch


def sound_onset(path, stream="a:0", floor_db=-40.0):
    """The first moment the sound is louder than floor_db (dBFS, 10 ms windows), in seconds, or None."""
    import numpy as np
    audio = decode_audio(path, channels=1, stream=stream)[:, 0]
    if not len(audio):
        return None
    win = RATE // 100
    n = len(audio) // win
    if n == 0:
        return None
    rms = np.sqrt((audio[:n * win].reshape(n, win) ** 2).mean(axis=1))
    level = 10 ** (floor_db / 20)
    loud = np.nonzero(rms >= level)[0]
    if not len(loud):
        return None
    k = int(loud[0])
    window = np.abs(audio[k * win:(k + 1) * win])
    first = int(np.argmax(window >= level)) if np.any(window >= level) else 0
    return (k * win + first) / RATE


_sting_lead = []


def sting_lead():
    """How far into the sting file its first sound louder than -40 dBFS comes (seconds)."""
    if not _sting_lead:
        f = CONTENT / "app" / app_manifest()["sting"]["file"]
        _sting_lead.append(sound_onset(f) or 0.0)
    return _sting_lead[0]


def still(video, t, out, width=360):
    """One frame of a video as a PNG (to look at what sync found)."""
    ffmpeg("-ss", f"{max(0.0, t):.4f}", "-i", video, "-frames:v", 1, "-vf", f"scale={width}:-2", out,
           what="a frame")


def sync(platform, name, sb, takes=None, offset=None, intro_at=None, launch_lag=0.15, quiet=False):
    """Works out a take's zero (seconds into its video) and its sound's offset (video time - sound time):
    sync.json, and intro-before.png / intro.png (the frames either side of the intro's start) to look at."""
    info = load_take(platform, name, takes)
    folder = Path(info["folder"])
    take = sb["takes"].get(name, {})
    has_intro = bool(take.get("intro", info.get("intro")))
    video = take_video(info)
    frames = video_frames(video, seconds=min(40.0, float(info.get("seconds", 40))))
    splash, intro, launch = find_intro(frames)
    t_intro = intro_at if intro_at is not None else (intro / FPS if intro is not None else None)
    t_launch = launch / FPS if launch is not None else None
    sound_file, stream = take_sound(info)
    onset = sound_onset(sound_file, stream) if sound_file.exists() else None
    method = "by hand" if offset is not None else None
    if has_intro and t_intro is None:
        raise PreviewError(f"take {name}: no intro found in its first {len(frames) / FPS:.0f} s (a navy splash, "
                           f"then the circle and wordmark): --intro-at SECONDS says where it starts")
    zero = t_intro if has_intro else (t_launch if t_launch is not None else 0.0)
    if offset is None:
        # where the sting starts on the sound's timeline: placed there (assembled), or heard there (recorded)
        sting = None
        if info.get("soundFrom") == "assembled" and (folder / "cues.json").exists():
            sting = next((s["at"] for c in read_json(folder / "cues.json") for s in c["sounds"]
                          if s["kind"] == "sting"), None)
        if sting is None and onset is not None:
            sting = onset - sting_lead()
        delay = float(sb.get("capture", {}).get(platform, {}).get("stingDelay", 0.0))
        if has_intro and sting is not None:
            offset = t_intro + delay - sting
            method = "the intro's first frame against the sting's start"
        elif info.get("soundFrom") == "assembled" and t_launch is not None:
            launched = next((e["t"] for e in read_events(folder) if e.get("event") == "launch"), None)
            if launched is not None:
                offset, method = t_launch - (launched + launch_lag), "the app's first frame against am start"
        if offset is None:
            offset, method = 0.0, "none needed (recorded together)" if info.get("soundFrom") == "recorded" \
                else "none found: 0"
    data = {"zero": round(zero, 4), "offset": round(offset, 4), "intro": t_intro, "launch": t_launch,
            "splash": splash / FPS if splash is not None else None, "onset": onset, "method": method, "made": now()}
    write_json(folder / "sync.json", data)
    if has_intro:
        still(video, t_intro - 1.0 / FPS, folder / "intro-before.png")
        still(video, t_intro, folder / "intro.png")
    if not quiet:
        where = (f"the intro{f'; the splash from {splash / FPS:.3f} s' if splash is not None else ''}"
                 if has_intro else "the app's first frame")
        print(f"  {platform}/{name}: zero {zero:.3f} s into the video ({where}); the sound {offset:+.3f} s "
              f"({method})")
        if has_intro:
            print(f"    look: {rel(folder / 'intro-before.png')} (the splash), {rel(folder / 'intro.png')} "
                  f"(the circle starting)")
    return data


def load_sync(platform, name, sb, takes=None):
    folder = take_dir(platform, name, takes)
    path = folder / "sync.json"
    if not path.exists():
        print(f"  {platform}/{name} isn't synced yet: syncing")
        return sync(platform, name, sb, takes)
    return read_json(path)


# ----- Captions -----

def caption_style(edl):
    w, h = TARGETS[edl["target"]]["size"]
    style = {"size": round(w * 0.068), "min": round(w * 0.05), "lines": 2, "width": 0.9, "top": round(h * 0.06),
             "bottom": round(h * 0.06), "padX": round(w * 0.04), "padY": round(w * 0.03), "radius": round(w * 0.03),
             "alpha": 0.92, "box": "navy", "colour": "white", "key": "gold", "weight": "bold"}
    style.update(edl.get("caption", {}))
    return style


def render_caption(text, size, style, at="top"):
    """One caption as an RGBA strip the width of the video: a navy box (opaque enough that its words keep 7:1
    over a white or a black picture) with the words in white, the starred ones gold. (image, y)."""
    from PIL import Image, ImageDraw
    from art.brand import colour
    from art.compose import ratio
    from art.text import draw_lines, face, fit
    w, h = size
    box_w = round(w * style["width"]) if style["width"] <= 1 else int(style["width"])
    f = face(style["weight"])
    font_size, lines = fit(f, text, box_w - 2 * style["padX"], style["size"], style["min"], style["lines"])
    leading = 1.18
    block = font_size * leading * (len(lines) - 1) + f.cap * font_size / f.upem
    box_h = int(round(block + 0.22 * font_size + 2 * style["padY"]))
    box = colour(style["box"])
    alpha = float(style["alpha"])
    for behind in ((0, 0, 0), (255, 255, 255)):
        shown = tuple(alpha * c + (1 - alpha) * b for c, b in zip(box, behind))
        for c in (style["colour"], style["key"]):
            if ratio(colour(c), shown) < 7.0:
                raise PreviewError(f"caption box alpha {alpha}: {c} words would be {ratio(colour(c), shown):.1f}:1 "
                                   f"over a {'white' if behind[0] else 'black'} picture (7:1 at least)")
    image = Image.new("RGBA", (w, box_h), (0, 0, 0, 0))
    x0 = (w - box_w) // 2
    big = Image.new("L", (box_w * 4, box_h * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, box_w * 4 - 1, box_h * 4 - 1), style["radius"] * 4, fill=255)
    mask = big.resize((box_w, box_h), Image.LANCZOS).point(lambda v: int(round(v * alpha)))
    fill = Image.new("RGBA", (box_w, box_h), box + (255,))
    fill.putalpha(mask)
    image.alpha_composite(fill, (x0, 0))
    inner = (x0 + style["padX"], style["padY"], x0 + box_w - style["padX"], box_h - style["padY"])
    draw_lines(image, f, lines, font_size, inner, colour(style["colour"]), key=colour(style["key"]), leading=leading)
    y = style["top"] if at == "top" else h - style["bottom"] - box_h if at == "bottom" else (h - box_h) // 2
    return image, y


# ----- Edit -----

def frames_of(seconds):
    return int(round(seconds * FPS))


def plan_cut(edl, sb, takes=None):
    """The cut, worked out: each clip's frames in its take's video, its sound's span in its sound file, and where
    it falls in the preview."""
    source = edl["source"]
    clips, at = [], 0
    infos, syncs = {}, {}
    for clip in edl["clips"]:
        for name in {clip["take"], (clip.get("sound") or {}).get("take", clip["take"])}:
            if name not in infos:
                infos[name] = load_take(source, name, takes)
                syncs[name] = load_sync(source, name, sb, takes)
        info, s = infos[clip["take"]], syncs[clip["take"]]
        first = frames_of(s["zero"] + clip["in"])
        count = frames_of(clip["out"] - clip["in"])
        if first < 0:
            raise PreviewError(f"clip {clip.get('scene', clip['take'])}: starts {-first / FPS:.2f} s before the "
                               f"take's video does")
        sound = clip.get("sound") or {}
        sname = sound.get("take", clip["take"])
        s_in = sound.get("in", clip["in"])
        ss = syncs[sname]
        # the sound file's time = the video's time - offset
        sound_start = ss["zero"] + s_in - ss["offset"]
        clips.append({"clip": clip, "take": clip["take"], "first": first, "count": count, "at": at / FPS,
                      "frames_at": at, "sound_take": sname, "sound_start": sound_start, "seconds": count / FPS,
                      "caption": clip_caption(edl, sb, clip)})
        at += count
    return clips, at / FPS, infos, syncs


def build_sound(clips, infos, out_path, fade_out):
    """The cut's sound, clip by clip, before loudness: a 48 kHz stereo WAV."""
    inputs, labels, graph = [], {}, []
    uses = {}
    for c in clips:
        uses.setdefault(c["sound_take"], 0)
        uses[c["sound_take"]] += 1
    for name in uses:
        f, stream = take_sound(infos[name])
        if not f.exists():
            raise PreviewError(f"take {name} has no sound ({rel(f)}): assemble it, or import one")
        labels[name] = (len(inputs), stream)
        inputs.append(f)
    split = {}
    for name, (i, stream) in labels.items():
        n = uses[name]
        base = f"[{i}:{stream}]aresample={RATE},aformat=sample_fmts=fltp:channel_layouts=stereo"
        if n == 1:
            graph.append(f"{base}[s{i}_0]")
        else:
            graph.append(f"{base},asplit={n}" + "".join(f"[s{i}_{k}]" for k in range(n)))
        split[name] = 0
    parts = []
    prev = None
    for k, c in enumerate(clips):
        i, _ = labels[c["sound_take"]]
        src = f"[s{i}_{split[c['sound_take']]}]"
        split[c["sound_take"]] += 1
        d = c["seconds"]
        start = c["sound_start"]
        chain = []
        if start + d <= 0:
            chain = [f"atrim=end=0.001", "asetpts=PTS-STARTPTS", f"volume=0"]
        elif start < 0:
            chain = [f"atrim=start=0:end={start + d:.6f}", "asetpts=PTS-STARTPTS",
                     f"adelay=delays={int(round(-start * 1000))}:all=1"]
        else:
            chain = [f"atrim=start={start:.6f}:end={start + d:.6f}", "asetpts=PTS-STARTPTS"]
        chain += [f"apad=whole_dur={d:.6f}", f"atrim=end={d:.6f}"]
        joined = prev is not None and prev[0] == c["sound_take"] and abs(prev[1] - start) < 1e-3
        nxt = clips[k + 1] if k + 1 < len(clips) else None
        joins_next = nxt is not None and nxt["sound_take"] == c["sound_take"] and \
            abs(start + d - nxt["sound_start"]) < 1e-3
        if not joined:
            chain.append("afade=t=in:d=0.008")
        if not joins_next:
            chain.append(f"afade=t=out:st={max(0.0, d - 0.008):.6f}:d=0.008")
        graph.append(f"{src}{','.join(chain)}[p{k}]")
        parts.append(f"[p{k}]")
        prev = (c["sound_take"], start + d)
    total = sum(c["seconds"] for c in clips)
    tail = f",afade=t=out:st={max(0.0, total - fade_out):.6f}:d={fade_out:.6f}" if fade_out else ""
    graph.append(f"{''.join(parts)}concat=n={len(parts)}:v=0:a=1{tail}[out]")
    args = []
    for f in inputs:
        args += ["-i", f]
    ffmpeg(*args, "-filter_complex", ";".join(graph), "-map", "[out]", "-c:a", "pcm_s16le", "-ar", RATE, "-ac", 2,
           out_path, what="the cut's sound")


def measure_loudness(path):
    """loudnorm's first pass over a file: its measured values, or None for silence."""
    need("ffmpeg")
    p = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-i", str(path), "-af",
                        f"loudnorm=I={LOUDNESS['I']}:TP={LOUDNESS['TP']}:LRA={LOUDNESS['LRA']}:print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p.stderr, re.S)
    if p.returncode != 0 or not m:
        raise PreviewError(f"loudnorm couldn't measure {rel(path)}")
    data = json.loads(m.group(0))
    try:
        if float(data["input_i"]) < -70:
            return None
    except ValueError:
        return None
    return data


def video_graph(clips, infos, captions, size):
    """The picture: each clip's frames scaled and cropped to the target, joined, captions on top."""
    w, h = size
    inputs, labels, graph = [], {}, []
    uses = {}
    for c in clips:
        uses[c["take"]] = uses.get(c["take"], 0) + 1
    for name in uses:
        labels[name] = len(inputs)
        inputs.append(take_video(infos[name]))
    split = {}
    for name, i in labels.items():
        n = uses[name]
        # 30 fps from a recording that only has frames when the screen changed; the last frame held so a clip near
        # the end never runs short
        base = f"[{i}:v]fps={FPS},tpad=stop_mode=clone:stop_duration=120"
        graph.append(f"{base}[v{i}_0]" if n == 1 else f"{base},split={n}" + "".join(f"[v{i}_{k}]" for k in range(n)))
        split[name] = 0
    parts = []
    for k, c in enumerate(clips):
        i = labels[c["take"]]
        src = f"[v{i}_{split[c['take']]}]"
        split[c["take"]] += 1
        graph.append(f"{src}trim=start_frame={c['first']}:end_frame={c['first'] + c['count']},setpts=PTS-STARTPTS,"
                     f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h},setsar=1,"
                     f"format=yuv420p[c{k}]")
        parts.append(f"[c{k}]")
    graph.append(f"{''.join(parts)}concat=n={len(parts)}:v=1:a=0[cut]")
    last = "[cut]"
    for k, (path, y, start, end) in enumerate(captions):
        j = len(inputs)
        inputs.append(path)
        out = f"[o{k}]"
        graph.append(f"{last}[{j}:v]overlay=x=0:y={y}:enable='gte(t,{start:.4f})*lt(t,{end:.4f})'{out}")
        last = out
    graph.append(f"{last}format=yuv420p[picture]")
    return inputs, graph


def edit(edl_path, sb, takes=None, out_dir=None, install=False):
    edl = load_edl(edl_path, sb)
    target = TARGETS[edl["target"]]
    size = tuple(target["size"])
    out_dir = Path(out_dir) if out_dir else BUILD / edl["target"]
    name = edl.get("name") or ("01_IPHONE_67" if edl["target"] == "appstore" else "preview")
    clips, total, infos, syncs = plan_cut(edl, sb, takes)
    print(f"{rel(edl_path)}: {len(clips)} clips, {total:.2f} s, {size[0]}x{size[1]}")
    style = caption_style(edl)
    captions, made = [], {}
    cap_dir = out_dir / "captions"
    if cap_dir.exists():
        for old in cap_dir.glob("*.png"):
            old.unlink()
    for k, c in enumerate(clips):
        if not c["caption"]:
            continue
        at = c["clip"].get("captionAt", "top")
        key = (c["caption"], at)
        if key not in made:
            image, y = render_caption(c["caption"], size, style, at)
            path = cap_dir / f"{len(made) + 1:02d}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path)
            made[key] = (path, y)
        path, y = made[key]
        # one caption over clips in a row that share it
        if captions and captions[-1][0] == path and abs(captions[-1][3] - c["at"]) < 1e-6:
            captions[-1] = (path, y, captions[-1][2], c["at"] + c["seconds"])
        else:
            captions.append((path, y, c["at"], c["at"] + c["seconds"]))
    sound = out_dir / "sound.wav"
    build_sound(clips, infos, sound, float(edl.get("fadeOut", 0.0)))
    measured = measure_loudness(sound)
    if measured:
        loud = (f"loudnorm=I={LOUDNESS['I']}:TP={LOUDNESS['TP']}:LRA={LOUDNESS['LRA']}:"
                f"measured_I={measured['input_i']}:measured_TP={measured['input_tp']}:"
                f"measured_LRA={measured['input_lra']}:measured_thresh={measured['input_thresh']}:"
                f"offset={measured['target_offset']}:linear=true,aresample={RATE}")
        print(f"  sound: {float(measured['input_i']):.1f} LUFS, peak {float(measured['input_tp']):.1f} dBTP -> "
              f"{LOUDNESS['I']:.0f} LUFS")
    else:
        loud = f"aresample={RATE}"
        print("  sound: silent (nothing to bring to -16 LUFS)")
    inputs, graph = video_graph(clips, infos, captions, size)
    graph.append(f"[{len(inputs)}:a]{loud},aformat=sample_fmts=fltp:channel_layouts=stereo[sound]")
    args = []
    for f in inputs:
        args += ["-i", f]
    args += ["-i", sound]
    video = out_dir / f"{name}.mp4"
    tmp = video.with_name(video.stem + ".tmp.mp4")
    ffmpeg(*args, "-filter_complex", ";".join(graph), "-map", "[picture]", "-map", "[sound]", *VIDEO_CODEC,
           *AUDIO_CODEC, "-t", f"{total:.6f}", "-movflags", "+faststart", tmp, what="the cut")
    os.replace(tmp, video)
    print(f"  {rel(video)}")
    if target["srt"]:
        srt = video.with_suffix(".srt")
        entries = subtitles(clips, infos, edl, sb)
        srt.write_text(format_srt(entries), encoding="utf-8", newline="\n")
        print(f"  {rel(srt)}: {len(entries)} caption{'s' if len(entries) != 1 else ''}")
    for c in captions:
        print(f"  caption {rel(c[0])} {c[2]:.2f}-{c[3]:.2f} s")
    errors = check(video, edl["target"])
    if install and edl["target"] in INSTALL:
        if errors:
            raise PreviewError("not installed: the check found errors")
        dest = INSTALL[edl["target"]] / video.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(video, dest)
        print(f"  installed: {rel(dest)}")
    return 1 if errors else 0


# ----- Subtitles (.srt): what's said, from the takes' cues -----

def words_between(line, start, t0, t1):
    """The words of a transcript line (starting at `start`) said between t0 and t1: [(word, time)]."""
    words = line.get("text", "").split()
    if not words:
        return []
    at = line.get("w")
    if not at or len(at) != len(words):
        span = float(line.get("len") or 0.1)
        at = [span * i / len(words) for i in range(len(words))]
    return [(wd, start + a) for wd, a in zip(words, at) if t0 <= start + a < t1]


def subtitles(clips, infos, edl, sb):
    """(start, end, text) in the preview's time: what's said in each clip (from its sound take's cues.json, words
    timed), and the sting as [Music]; the captions themselves when a take has no cues (a recorded sound)."""
    entries = []
    for c in clips:
        folder = Path(infos[c["sound_take"]]["folder"])
        cues = read_json(folder / "cues.json") if (folder / "cues.json").exists() else None
        if cues is None:
            if c["caption"]:
                entries.append((c["at"], c["at"] + c["seconds"], plain_caption(c["caption"])))
            continue
        t0, t1 = c["sound_start"], c["sound_start"] + c["seconds"]
        for cue in cues:
            for s in cue["sounds"]:
                for line in s.get("lines", []):
                    start = s["at"] + float(line.get("at", 0))
                    said = words_between(line, start, t0, t1)
                    if not said:
                        continue
                    end = min(t1, start + float(line.get("len") or 0))
                    chunks, current = [], []
                    for wd, t in said:
                        if current and (len(" ".join(x for x, _ in current + [(wd, t)])) > 84 or len(current) >= 14):
                            chunks.append(current)
                            current = []
                        current.append((wd, t))
                    if current:
                        chunks.append(current)
                    for n, chunk in enumerate(chunks):
                        a = chunk[0][1]
                        b = chunks[n + 1][0][1] if n + 1 < len(chunks) else end
                        text = " ".join(x for x, _ in chunk)
                        if n == 0 and line.get("who"):
                            text = f"{line['who']}: {text}"
                        if line.get("sound"):
                            text = f"[{line['sound']}] {text}"
                        a_out = c["at"] + (a - t0)
                        b_out = min(c["at"] + c["seconds"], c["at"] + (max(b, a + 0.8) - t0))
                        if b_out - a_out >= 0.3:
                            entries.append((a_out, b_out, text))
    entries.sort()
    tidy = []
    for a, b, text in entries:
        if tidy and tidy[-1][1] > a:
            tidy[-1] = (tidy[-1][0], a, tidy[-1][2])
        tidy.append((a, b, text))
    return [e for e in tidy if e[1] - e[0] >= 0.3]


def srt_time(t):
    ms = int(round(max(0.0, t) * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def wrap_srt(text, width=42):
    words, lines, line = text.split(), [], ""
    for wd in words:
        if line and len(line) + 1 + len(wd) > width:
            lines.append(line)
            line = wd
        else:
            line = f"{line} {wd}".strip()
    if line:
        lines.append(line)
    return "\n".join(lines)


def format_srt(entries):
    return "".join(f"{i}\n{srt_time(a)} --> {srt_time(b)}\n{wrap_srt(text)}\n\n"
                   for i, (a, b, text) in enumerate(entries, 1))


# ----- Check -----

def check(path, target=None):
    """A video against its store's rules; prints what it finds and returns the errors."""
    path = Path(path)
    errors, warnings = [], []
    if not path.exists():
        raise PreviewError(f"{rel(path)} isn't there")
    info = ffprobe(path)
    streams = info.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
    seconds = float(info.get("format", {}).get("duration") or 0)
    if target is None and video:
        size = (int(video["width"]), int(video["height"]))
        target = next((t for t, spec in TARGETS.items() if size in (spec["size"], spec["size"][::-1])), None)
    spec = TARGETS.get(target)
    if video is None:
        errors.append("no picture")
    else:
        size = (int(video["width"]), int(video["height"]))
        if spec and size not in (spec["size"], spec["size"][::-1]):
            errors.append(f"{size[0]}x{size[1]}; {target} wants {spec['size'][0]}x{spec['size'][1]} (or turned)")
        if video.get("codec_name") != "h264":
            errors.append(f"the picture is {video.get('codec_name')}, not H.264")
        elif video.get("profile") != "High":
            errors.append(f"H.264 {video.get('profile')} profile, not High")
        if int(video.get("level") or 0) > 40:
            errors.append(f"H.264 level {int(video['level']) / 10}, above 4.0")
        if video.get("pix_fmt") != "yuv420p":
            errors.append(f"pixels are {video.get('pix_fmt')}, not yuv420p")

        def rate(text):
            num, _, den = (text or "0/1").partition("/")
            return float(num) / float(den) if den and float(den) else 0.0
        r, avg = rate(video.get("r_frame_rate")), rate(video.get("avg_frame_rate"))
        if max(r, avg) > 30.01:
            errors.append(f"{max(r, avg):.2f} frames a second; 30 at most")
        if abs(r - avg) > 0.05:
            errors.append(f"the frame rate isn't constant ({r:.3f} and on average {avg:.3f})")
        bitrate = int(video.get("bit_rate") or 0)
        if bitrate > 12_500_000:
            warnings.append(f"the picture is {bitrate / 1e6:.1f} Mbps; Apple suggests 10 to 12")
    if audio is None:
        errors.append("no sound track (stereo AAC is wanted, even if quiet)")
    else:
        if audio.get("codec_name") != "aac":
            errors.append(f"the sound is {audio.get('codec_name')}, not AAC")
        if int(audio.get("channels") or 0) != 2:
            errors.append(f"the sound isn't stereo ({audio.get('channels')} channel(s))")
        if str(audio.get("sample_rate")) not in ("44100", "48000"):
            errors.append(f"the sound is {audio.get('sample_rate')} Hz, not 44,100 or 48,000")
    if video and audio:
        vd, ad = float(video.get("duration") or seconds), float(audio.get("duration") or seconds)
        if abs(vd - ad) > 0.1:
            errors.append(f"the picture ({vd:.2f} s) and the sound ({ad:.2f} s) differ by more than 0.1 s")
    low, high = spec["seconds"] if spec else (15.0, 30.0)
    if not low <= seconds <= high:
        (errors if (spec or {}).get("strict", True) else warnings).append(
            f"{seconds:.2f} s; {target or 'a preview'} wants {low:.0f} to {high:.0f}")
    if path.stat().st_size > 500 * 1024 * 1024:
        errors.append("over 500 MB")
    if audio:
        p = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-i", str(path), "-vn", "-af", "ebur128=peak=true",
                            "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        loud = re.findall(r"I:\s+(-?[\d.]+) LUFS", p.stderr)
        peak = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", p.stderr)
        if loud:
            lufs = float(loud[-1])
            if lufs > -70 and abs(lufs - LOUDNESS["I"]) > 1.5:
                warnings.append(f"the sound is {lufs:.1f} LUFS; the apps' level is {LOUDNESS['I']:.0f}")
        if peak and peak[-1] != "-inf" and float(peak[-1]) > LOUDNESS["TP"] + 0.5:
            warnings.append(f"the sound peaks at {float(peak[-1]):.1f} dBTP; {LOUDNESS['TP']:.0f} at most is safe")
    if target == "appstore" and not re.search(r"IPHONE_(67|65|61|58|55|47|40)", path.name.upper()):
        warnings.append("the name doesn't say the iPhone size (01_IPHONE_67.mp4): deliver would skip it")
    if spec and spec["srt"]:
        srt = path.with_suffix(".srt")
        if not srt.exists():
            warnings.append(f"no {srt.name} next to it (YouTube's captions)")
        else:
            last = 0.0
            for block in srt.read_text(encoding="utf-8").strip().split("\n\n"):
                rows = block.splitlines()
                m = re.fullmatch(r"(\d\d):(\d\d):(\d\d),(\d{3}) --> (\d\d):(\d\d):(\d\d),(\d{3})", rows[1]) \
                    if len(rows) >= 3 else None
                if not m:
                    errors.append(f"{srt.name}: an entry isn't index, times, text: {block[:60]!r}")
                    break
                g = [int(x) for x in m.groups()]
                a = g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000
                b = g[4] * 3600 + g[5] * 60 + g[6] + g[7] / 1000
                if b <= a or a < last - 1e-3 or b > seconds + 0.05:
                    errors.append(f"{srt.name}: entry {rows[0]} is out of order or past the end")
                    break
                last = b
    name = rel(path)
    print(f"{name}: {seconds:.2f} s" + (f", {video['width']}x{video['height']}" if video else "") +
          (f" ({target})" if target else ""))
    for w in warnings:
        print(f"  warning: {w}")
    for e in errors:
        print(f"  error: {e}")
    print(f"  {len(errors)} error{'s' if len(errors) != 1 else ''}, {len(warnings)} warning"
          f"{'s' if len(warnings) != 1 else ''}")
    return errors


# ----- Capturing -----

def take_names(sb, wanted):
    names = [t for t in (wanted or "").split(",") if t] or list(sb["takes"])
    unknown = [t for t in names if t not in sb["takes"]]
    if unknown:
        raise PreviewError(f"no take called {', '.join(unknown)} (the storyboard has {', '.join(sb['takes'])})")
    return names


SCRCPY_FLAGS = ("--no-playback", "--record", "--time-limit", "--audio-codec", "--max-fps")


def scrcpy_ready():
    """(whether scrcpy can record a take here, why not): 2.1 or later with every flag this uses (--time-limit
    stops it cleanly, so the MP4 is finished)."""
    exe = shutil.which("scrcpy")
    if not exe:
        return False, "scrcpy isn't installed (winget install Genymobile.scrcpy; the owner approves installs)"
    p = subprocess.run([exe, "--version"], capture_output=True, text=True, errors="replace")
    m = re.search(r"scrcpy (\d+)\.(\d+)", p.stdout + p.stderr)
    if not m or (int(m.group(1)), int(m.group(2))) < (2, 1):
        return False, f"scrcpy {m.group(1) + '.' + m.group(2) if m else '?'} is older than 2.1"
    p = subprocess.run([exe, "--help"], capture_output=True, text=True, errors="replace")
    missing = [f for f in SCRCPY_FLAGS if f not in p.stdout + p.stderr]
    if missing:
        return False, f"this scrcpy has no {', '.join(missing)}"
    return True, f"scrcpy {m.group(1)}.{m.group(2)}"


def capture_android(sb, args):
    import store_shots as ss
    names = take_names(sb, args.takes)
    scenes = ss.load_scenes()
    types = scenes["extras"].get("types", {})
    component = ss.component_of(scenes)
    capture = sb.get("capture", {}).get("android", {})
    size = capture.get("size", [1080, 1920])
    ready, why = scrcpy_ready() if args.scrcpy != "off" else (False, "--scrcpy off")
    if args.scrcpy == "on" and not ready:
        raise PreviewError(why)
    recorder = "scrcpy" if ready else "screenrecord"
    if not ready:
        print(f"recording with adb's screenrecord, the sound put together from content/ ({why})")
    if args.dry_run:
        adb = ss.Adb("adb", args.serial or "emulator-5554", dry=True)
    else:
        if ss.STATE.exists():
            raise PreviewError(f"a run didn't put the emulator back yet ({rel(ss.STATE)}): "
                               f"py -3.13 tools/store_shots.py restore first")
        adb = ss.pick_device(ss.find_adb(), args.serial, args.any_device)
        dump = adb.shell(f"dumpsys package {scenes['package']}")
        if "DEBUGGABLE" not in dump:
            raise PreviewError(f"{scenes['package']} isn't the debug build (android\\gradlew.bat -p android "
                               f":app:installDebug): the launch extras are in the debug build only")
    print(f"{adb.serial}: {len(names)} take{'s' if len(names) != 1 else ''} with {recorder}")
    state = None if args.dry_run else ss.save_state(adb, scenes["package"], not args.no_app_data)
    failed = []
    try:
        ss.enter_demo(adb, scenes.get("demo", {}))
        ss.grant(adb, scenes["package"], 35 if args.dry_run else
                 int(adb.shell("getprop ro.build.version.sdk").strip() or 0))
        adb.shell(f"wm size {size[0]}x{size[1]}")
        adb.shell(f"wm density {capture['density']}" if capture.get("density") else "wm density reset")
        adb.put_setting("system", "accelerometer_rotation", "0")
        adb.put_setting("system", "user_rotation", "0")
        adb.put_setting("system", "font_scale", str(capture.get("fontScale", 1.0)))
        if not args.dry_run:
            time.sleep(2.0)
        for name in names:
            try:
                record_android(adb, ss, sb, name, component, types, recorder, args, scenes["package"])
            except (PreviewError, ss.ShotError) as e:
                failed.append(f"{name}: {e}")
                print(f"  failed: {e}")
    finally:
        if state is not None:
            ss.finish_restore(adb, state)
    if args.dry_run:
        return 0
    for name in names:
        if not any(f.startswith(f"{name}:") for f in failed):
            info = load_take("android", name, args.takes_dir)
            if info.get("sound") != "video":
                try:
                    assemble("android", name, sb, args.takes_dir)
                except PreviewError as e:
                    failed.append(f"{name}: {e}")
                    print(f"  {name}: the sound wasn't put together: {e}")
                    continue
            try:
                sync("android", name, sb, args.takes_dir)
            except PreviewError as e:
                failed.append(f"{name}: {e}")
                print(f"  {name}: not synced: {e}")
    for f in failed:
        print(f"  failed: {f}")
    return 1 if failed else 0


def record_android(adb, ss, sb, name, component, types, recorder, args, package):
    take = sb["takes"][name]
    folder = take_dir("android", name, args.takes_dir)
    seconds = int(math.ceil(take["seconds"]))
    extras = {k: v for k, v in take.get("extras", {}).items() if v is not None}
    print(f"  {name}: {seconds} s")
    if not args.dry_run:
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    video = folder / "video.mp4"
    remote = "/sdcard/eag-take.mp4"
    t0 = adb.device_time()
    reader = ss.LogReader(adb, t0 - 0.2, [LOG_TAG, "ActivityTaskManager", "ActivityManager"])
    proc = None
    try:
        if recorder == "scrcpy":
            cmd = ["scrcpy", "-s", adb.serial, "--no-playback", f"--record={video}", "--video-codec=h264",
                   "--video-bit-rate=16M", f"--max-fps={FPS}", "--audio-codec=aac", "--audio-bit-rate=256K",
                   f"--time-limit={seconds}"]
        else:
            cmd = adb.cmd("shell", f"screenrecord --time-limit {seconds} --bit-rate 16000000 {remote}")
        if args.dry_run:
            print("  " + " ".join(str(c) for c in cmd))
        else:
            log = folder / "recorder.log"            # a file, not a pipe: a chatty recorder never blocks on it
            with open(log, "wb") as out:
                proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
            time.sleep(1.5)                          # the recorder's encoder starts
            if proc.poll() is not None:
                raise PreviewError(f"{recorder} stopped at once: "
                                   f"{log.read_text(encoding='utf-8', errors='replace').strip()[-300:]}")
        launch = adb.device_time()
        said = adb.shell(ss.am_start(component, extras, types), timeout=90)
        if "Error" in said or "Exception" in said:
            raise PreviewError(f"am start: {said.strip()}")
        pid = None if args.dry_run else adb.pid(package)
        if not args.dry_run:
            try:
                proc.wait(timeout=seconds + 20)
            except subprocess.TimeoutExpired:
                proc.terminate()
                raise PreviewError(f"{recorder} didn't stop after {seconds} s")
    finally:
        reader.close()
        if proc is not None and proc.poll() is None:
            proc.terminate()
    if args.dry_run:
        print(f"  (then: adb pull {remote}, the log lines into events.jsonl, the sound from content/, sync)")
        return
    if recorder == "screenrecord":
        adb.run("pull", remote, str(video), timeout=120)
        adb.shell(f"rm -f {remote}", check=False)
    if not video.exists() or video.stat().st_size == 0:
        raise PreviewError(f"no recording came back from {recorder}")
    events = [{"t": round(launch - t0, 4), "event": "launch"}]
    for t, line_pid, tag, msg in reader.lines:
        if tag == LOG_TAG and (pid is None or line_pid == pid):
            events.append({"t": round(t - t0, 4), "tag": tag, "pid": line_pid, "msg": msg})
        elif tag in ("ActivityTaskManager", "ActivityManager") and re.search(
                r"Displayed com\.epicaudiogames\.app/", msg):
            events.append({"t": round(t - t0, 4), "event": "displayed", "tag": tag, "msg": msg})
    events.sort(key=lambda e: e["t"])
    (folder / "events.jsonl").write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events),
                                         encoding="utf-8", newline="\n")
    info = {"platform": "android", "take": name, "recorder": recorder, "seconds": media_seconds(video),
            "video": video.name, "intro": bool(take.get("intro")), "deviceStart": t0, "made": now(),
            "sound": "sound.wav", "soundFrom": "assembled"}
    if recorder == "scrcpy":
        streams = ffprobe(video).get("streams", [])
        if any(s.get("codec_type") == "audio" for s in streams) and sound_onset(video) is not None:
            info.update({"sound": "video", "soundFrom": "recorded"})
        else:
            print("    the recording has no sound (an emulator started with -no-audio?): put together from content/")
    info["folder"] = folder
    save_take(info)
    lines = [e for e in events if e.get("tag") == LOG_TAG]
    print(f"    {rel(video)}: {info['seconds']:.1f} s; {len(lines)} {LOG_TAG} line{'s' if len(lines) != 1 else ''}"
          f"{'' if lines else ' (no DebugLaunch lines: is it the debug build with DebugLaunch.kt?)'}")


def ios_arguments(extras):
    out = []
    for key, value in extras.items():
        if value is None:
            continue
        out += [f"-{key}", ("YES" if value else "NO") if isinstance(value, bool) else str(value)]
    return out


def capture_ios(sb, args):
    names = take_names(sb, args.takes)
    capture = sb.get("capture", {}).get("ios", {})
    bundle = capture.get("bundle", "com.epicaudiogames.app")
    device = args.audio_device or capture.get("audioDevice", ":BlackHole 2ch")
    if sys.platform != "darwin" and not args.dry_run:
        raise PreviewError("capture-ios runs on the Mac (Xcode's simulator); --dry-run shows its commands")
    udid = args.udid
    if not udid and not args.dry_run:
        p = subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True)
        booted = [d for ds in json.loads(p.stdout or "{}").get("devices", {}).values() for d in ds
                  if d.get("state") == "Booted"]
        if len(booted) != 1:
            raise PreviewError(f"{len(booted)} simulators are booted: boot one (an iPhone 17 Pro Max), or --udid")
        udid = booted[0]["udid"]
    udid = udid or "<booted udid>"
    status = ["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "discharging",
              "--batteryLevel", "100", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4"]

    def run(cmd):
        if args.dry_run:
            print("  " + " ".join(cmd))
            return
        p = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
        if p.returncode != 0:
            raise PreviewError(f"{' '.join(cmd[:4])}: {(p.stderr or p.stdout).strip()[-300:]}")

    run(status)
    failed = []
    try:
        for name in names:
            take = sb["takes"][name]
            folder = take_dir("ios", name, args.takes_dir)
            video, sound = folder / "video.mov", folder / "sound.wav"
            launch = ["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle] + \
                ios_arguments(take.get("extras", {}))
            rec = ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", str(video)]
            snd = ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-f", "avfoundation", "-i", device,
                   "-ac", "2", "-ar", str(RATE), "-y", str(sound)]
            print(f"  {name}: {take['seconds']} s")
            if args.dry_run:
                print("  " + " ".join(rec) + " &")
                print("  " + " ".join(snd[:-1]) + f" {sound} &")
                print("  " + " ".join(launch))
                print(f"  (after {take['seconds']} s: stop both with Ctrl+C / q, then sync)")
                continue
            if folder.exists():
                shutil.rmtree(folder)
            folder.mkdir(parents=True)
            subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)
            with open(folder / "recorder.log", "wb") as log_r, open(folder / "sound.log", "wb") as log_s:
                r = subprocess.Popen(rec, stdout=log_r, stderr=subprocess.STDOUT)
                s = subprocess.Popen(snd, stdin=subprocess.PIPE, stdout=log_s, stderr=subprocess.STDOUT)
            try:
                time.sleep(1.5)
                if r.poll() is not None or s.poll() is not None:
                    raise PreviewError("the recording didn't start (is BlackHole 2ch installed? "
                                       "ffmpeg -f avfoundation -list_devices true -i \"\"; see "
                                       f"{rel(folder / 'recorder.log')} and sound.log)")
                run(launch)
                time.sleep(float(take["seconds"]))
            finally:
                if s.poll() is None:
                    try:
                        s.communicate(b"q", timeout=10)
                    except subprocess.TimeoutExpired:
                        s.kill()
                if r.poll() is None:
                    r.send_signal(signal.SIGINT)
                    try:
                        r.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        r.kill()
            info = {"platform": "ios", "take": name, "recorder": "simctl", "seconds": media_seconds(video),
                    "video": video.name, "sound": sound.name, "soundFrom": "recorded",
                    "intro": bool(take.get("intro")), "made": now(), "folder": folder}
            save_take(info)
            try:
                sync("ios", name, sb, args.takes_dir)
            except PreviewError as e:
                failed.append(f"{name}: {e}")
                print(f"  {name}: not synced: {e}")
    finally:
        run(["xcrun", "simctl", "status_bar", udid, "clear"])
    return 1 if failed else 0


def import_take(sb, args):
    if args.take not in sb["takes"]:
        raise PreviewError(f"no take called {args.take} in the storyboard")
    src = Path(args.file)
    if not src.exists():
        raise PreviewError(f"{src} isn't there")
    folder = take_dir(args.platform, args.take, args.takes_dir)
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    video = folder / f"video{src.suffix.lower()}"
    shutil.copyfile(src, video)
    info = {"platform": args.platform, "take": args.take, "recorder": "import", "seconds": media_seconds(video),
            "video": video.name, "intro": bool(sb["takes"][args.take].get("intro")), "made": now(),
            "source": str(src), "folder": folder}
    has_sound = any(s.get("codec_type") == "audio" for s in ffprobe(video).get("streams", []))
    if args.sound:
        ffmpeg("-i", args.sound, "-vn", "-ac", 2, "-ar", RATE, "-c:a", "pcm_s16le", folder / "sound.wav",
               what="the sound")
        info.update({"sound": "sound.wav", "soundFrom": "recorded"})
    elif has_sound:
        info.update({"sound": "video", "soundFrom": "recorded"})
    else:
        info.update({"sound": "sound.wav", "soundFrom": "assembled"})
    save_take(info)
    print(f"  {rel(video)}: {info['seconds']:.1f} s, sound {info['sound']}")
    if info["soundFrom"] == "assembled":
        if not (folder / "events.jsonl").exists():
            print("  no sound and no events.jsonl: give --sound, or put the take's log lines in events.jsonl and "
                  "run assemble")
            return 0
        assemble(args.platform, args.take, sb, args.takes_dir)
    sync(args.platform, args.take, sb, args.takes_dir)
    return 0


# ----- Plan -----

def plan(sb, args):
    print(f"{rel(args.storyboard)}: {sb['game']}, {len(sb['scenes'])} scenes, takes {', '.join(sb['takes'])}")
    for s in sb["scenes"]:
        span = f"{s['from']:5.1f}-{s['to']:5.1f} s  " if "from" in s and "to" in s else ""
        print(f"  {span}{s['id']}: {plain_caption(s['caption']) if s.get('caption') else '(no caption)'}")
    try:
        import store_shots as ss
        scenes = ss.load_scenes()
        types, component = scenes["extras"].get("types", {}), ss.component_of(scenes)
    except Exception as e:                  # the scenes file is store_shots.py's; the plan goes on without it
        print(f"  (brand/scenes.json: {e})")
        ss, types, component = None, {}, None
    for name, take in sb["takes"].items():
        print(f"\ntake {name}: {take['seconds']} s{', with the intro' if take.get('intro') else ''}")
        if take.get("about"):
            print(f"  {take['about']}")
        extras = {k: v for k, v in take.get("extras", {}).items() if v is not None}
        if ss:
            print(f"  android: adb shell {ss.am_start(component, extras, types)}")
        print(f"  ios: xcrun simctl launch --terminate-running-process booted com.epicaudiogames.app "
              f"{' '.join(ios_arguments(extras))}")
        events, info, synced = [], None, None
        folder = take_dir("android", name, args.takes_dir)
        if (folder / "take.json").exists():
            info = load_take("android", name, args.takes_dir)
            events = read_events(folder)
            synced = read_json(folder / "sync.json") if (folder / "sync.json").exists() else None
        for cue in take.get("sound", []):
            sounds, length, notes, label = cue_sounds(cue, sb["game"])
            where = "; ".join([f"ends at {describe_anchor(a)}" for a in as_list(cue.get("end"))] +
                              [f"starts at {describe_anchor(a)}" for a in as_list(cue.get("at"))])
            print(f"  {label}: {length:.2f} s, {where}")
            for s in sounds:
                first = next((line["text"] for line in s["lines"] if line.get("text")), "")
                print(f"      +{s['at']:6.2f}  {s['name']}  {s['dur']:.2f} s"
                      f"{' (bed, volume ' + str(s['volume']) + ')' if s['kind'] == 'bed' else ''}"
                      f"{'  “' + first[:60] + '…”' if first else ''}")
            for n in notes:
                print(f"      note: {n}")
        if info is not None:
            print(f"  captured on Android: {info['seconds']:.1f} s with {info['recorder']}, sound "
                  f"{info.get('soundFrom')}; {len([e for e in events if e.get('tag') == LOG_TAG])} {LOG_TAG} lines")
            if synced:
                print(f"  synced: zero {synced['zero']:.3f} s into the video, sound offset {synced['offset']:+.3f} s "
                      f"({synced['method']})")
                try:
                    placed, _ = place_sounds(take, events, sb["game"])
                except PreviewError as e:
                    print(f"  (not placed: {e})")
                    placed = []
                for p in placed:
                    t = p["start"] + synced["offset"] - synced["zero"]
                    print(f"    from zero {t:7.2f}-{t + p['dur']:6.2f} s  {p['name']}")
                    for s in p["sounds"]:
                        for line in s["lines"]:
                            a = s["at"] + float(line.get("at", 0)) + synced["offset"] - synced["zero"]
                            print(f"      {a:7.2f}-{a + float(line.get('len') or 0):6.2f}  "
                                  f"{(line.get('who') + ': ') if line.get('who') else ''}{line.get('text', '')[:70]}")
    for edl_path in args.edl or sorted(p for p in PREVIEWS.glob("*.json") if p.name != STORYBOARD.name):
        edl = read_json(edl_path)
        errors, warnings = check_edl(edl, sb)
        print(f"\n{rel(edl_path)}: {edl.get('target')} from {edl.get('source')} takes")
        at = 0.0
        for clip in edl.get("clips", []):
            d = round((clip["out"] - clip["in"]) * FPS) / FPS
            cap = clip_caption(edl, sb, clip)
            sound = clip.get("sound")
            more = f", sound {sound['take']} from {sound.get('in', clip['in'])}" if sound else ""
            print(f"  {at:6.2f}-{at + d:6.2f}  {clip['take']} {clip['in']:.2f}-{clip['out']:.2f}{more}  "
                  f"{plain_caption(cap) if cap else ''}")
            at += d
        print(f"  {at:.2f} s in all")
        for w in warnings:
            print(f"  warning: {w}")
        for e in errors:
            print(f"  error: {e}")
    return 0


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter,
                                 epilog="\n\n".join(__doc__.split("\n\n")[1:]))
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--storyboard", type=Path, default=STORYBOARD,
                        help="the storyboard (default brand/previews/storyboard.json)")
    common.add_argument("--takes-dir", type=Path, default=None,
                        help="where the takes are (default build/preview/takes)")
    sub = ap.add_subparsers(dest="command", required=True)

    def add(name, **kw):
        return sub.add_parser(name, parents=[common], **kw)

    p = add("plan", help="check the storyboard and EDLs; each take's sounds and, once captured, their times")
    p.add_argument("edl", nargs="*", type=Path, help="EDLs to show (default every one in brand/previews/)")

    p = add("capture-android", help="record takes on the emulator (scrcpy, else screenrecord + assemble)")
    p.add_argument("--takes", help="only these takes, e.g. main,settings (default all)")
    p.add_argument("--serial", help="the emulator (default: the only one running)")
    p.add_argument("--scrcpy", choices=["auto", "on", "off"], default="auto",
                   help="record with scrcpy (picture and sound): auto when 2.1 or later is installed")
    p.add_argument("--no-app-data", action="store_true", help="don't keep the app's saved games and settings")
    p.add_argument("--any-device", action="store_true", help="allow a device that isn't an emulator")
    p.add_argument("--dry-run", action="store_true", help="print the commands; no device needed")

    p = add("capture-ios", help="(the Mac) record takes on the booted simulator, sound via BlackHole 2ch")
    p.add_argument("--takes", help="only these takes (default all)")
    p.add_argument("--udid", help="the simulator (default: the booted one)")
    p.add_argument("--audio-device", help="ffmpeg's avfoundation input (default \":BlackHole 2ch\")")
    p.add_argument("--dry-run", action="store_true", help="print the commands (works anywhere)")

    p = add("import", help="a recording made some other way (QuickTime, a phone) as a take")
    p.add_argument("file", help="the video (.mov, .mp4)")
    p.add_argument("--take", required=True, help="the storyboard take it is")
    p.add_argument("--platform", choices=["android", "ios"], required=True)
    p.add_argument("--sound", help="its sound, when recorded apart (else the video's own)")

    p = add("assemble", help="an Android take's sound from content/ and its log lines, again")
    p.add_argument("take")
    p.add_argument("--platform", choices=["android", "ios"], default="android")

    p = add("sync", help="line a take's sound up with its picture (sync.json)")
    p.add_argument("take")
    p.add_argument("--platform", choices=["android", "ios"], default="android")
    p.add_argument("--offset", type=float, help="the sound's offset by hand (seconds; + plays it later)")
    p.add_argument("--intro-at", type=float, help="the intro's first frame by hand (seconds into the video)")

    p = add("edit", help="cut an EDL into the store's video (and .srt for Play)")
    p.add_argument("edl", type=Path, help="brand/previews/appstore.json or play.json")
    p.add_argument("--out", type=Path, help="write here (default build/preview/<target>/)")
    p.add_argument("--install", action="store_true",
                   help="App Store: copy the checked cut to ios/fastlane/app_previews/en-US/")

    p = sub.add_parser("check", help="a video against its store's rules (ffprobe)")
    p.add_argument("video", type=Path)
    p.add_argument("--target", choices=list(TARGETS), help="default: from its size")

    args = ap.parse_args(argv)
    try:
        if args.command == "check":
            return 1 if check(args.video, args.target) else 0
        sb = load_storyboard(args.storyboard)
        if args.command == "plan":
            return plan(sb, args)
        if args.command == "capture-android":
            return capture_android(sb, args)
        if args.command == "capture-ios":
            return capture_ios(sb, args)
        if args.command == "import":
            return import_take(sb, args)
        if args.command == "assemble":
            if args.take not in sb["takes"]:
                raise PreviewError(f"no take called {args.take} in the storyboard")
            assemble(args.platform, args.take, sb, args.takes_dir)
            return 0
        if args.command == "sync":
            if args.take not in sb["takes"]:
                raise PreviewError(f"no take called {args.take} in the storyboard")
            sync(args.platform, args.take, sb, args.takes_dir, args.offset, args.intro_at)
            return 0
        if args.command == "edit":
            return edit(args.edl, sb, args.takes_dir, args.out, args.install)
    except PreviewError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("stopped", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
