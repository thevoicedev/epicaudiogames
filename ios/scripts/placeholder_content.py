"""Makes placeholder content: a quiet tone for every clip the games play, and a plain cover for each game.

The real content/ (about 190 MB of voices and music, built by tools/) isn't on every machine. This writes a tree with
the same paths and lengths, so the iOS app can be built, run and timed without it:

- <out>/<id>/<path>.m4a for every clip and bed that games/<id>/map.json plays (tools/validate.py's plays()), and for
  Nuclear War's recordings and mixes (games/nuclear-war/clips.json);
- <out>/nuclear-war/<path>.opus for Don's lines (clips.json "voice"), Ogg Opus like the real ones
  (tools/games/nuclearwar.py);
- <out>/<id>/cover.jpg, 676x380 like the real covers (tools/fetch_art.py): the website's cover of the game
  (web/public/covers/<id>.jpg, scaled up to 676x380 when smaller) when there is one, else a plain gradient.

Each clip lasts its "dur" (or 2 s). It is a soft tone whose pitch comes from its path, so neighbouring clips sound
different, with a short high blip at its start, so a gap or overlap between clips is easy to hear. Beds hum lower and
waver, under the rest.

The clips a game's packs add (games/<id>/packs/<pack>.json) go to <packs>/<pack>/ instead, as an installed pack's
folder: pack.json, .version and the audio the free game doesn't have (as tools/make_pack.py picks it). The app's
bundle never has them, as with the real content.

Usage (from the repo root): python3 ios/scripts/placeholder_content.py [--out build/placeholder-content]
    [--packs build/placeholder-packs | --no-packs] [--covers web/public/covers] [--game noodle-rush] [--force]
    [--verify]
Then build the app with EPIC_CONTENT_DIR=<out> (ios/scripts/bundle_content.sh).
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAMES = ROOT / "games"
DEFAULT_DUR = 2.0
COVER = "676x380"
# The website's covers of the games (web/public/covers/<id>.jpg), used as the placeholder covers when there.
WEB_COVERS = ROOT / "web" / "public" / "covers"
# How each kind of clip is encoded: sample rate and bitrate. Speech is 24 kHz like the real tts clips, mixes 32 kHz,
# the skill's recordings 44.1 kHz (their CDN MP3s); Don's lines are Opus at 48 kHz.
AAC = ["-c:a", "aac", "-b:a", "16k", "-movflags", "+faststart"]
OPUS = ["-c:a", "libopus", "-b:a", "12k", "-application", "audio"]
RATES = {"tts": 24000, "mix": 32000}
# Cover colours: the speaker colours of ui/Theme.kt, one per game.
COLOURS = ["2F72B9", "D9480F", "2B8A3E", "862E9C", "C2255C", "1098AD", "E67700", "5F3DC4"]


def plays(game_map):
    """Every clip and bed the map plays, with its length, inside picks and cases too (tools/validate.py)."""
    out = {}

    def walk(steps):
        for s in steps or []:
            if "play" in s:
                out.setdefault(s["play"], (s.get("dur"), "sfx" if s.get("sfx") else "clip"))
            elif s.get("bed"):
                out.setdefault(s["bed"], (s.get("dur"), "bed"))
            elif "pick" in s:
                for option in s["pick"]:
                    walk(option)
            elif "by" in s:
                for option in (s.get("cases") or {}).values():
                    walk(option)
                walk(s.get("else"))

    for node in game_map["nodes"].values():
        walk(node.get("say"))
        ask = node.get("ask")
        if ask:
            walk(ask.get("reprompt"))
            if isinstance(ask.get("else"), dict):
                walk(ask["else"].get("say"))
    return out


def nuclear_plays(clips):
    """Nuclear War's clips.json: the recordings and mixes (.m4a here), and Don's lines (.opus)."""
    out = {}
    for c in clips["clips"].values():
        out[c["play"]] = (c.get("dur"), "sfx" if c.get("sfx") else "clip")
    for c in clips["mixes"].values():
        out[c["play"]] = (c.get("dur"), "clip")
    for c in clips["voice"].values():
        out[c["play"]] = (c.get("dur"), "voice")
    return out


def tone(path, kind, dur):
    """The aevalsrc expression for a clip: a soft tone, with a blip at the start (beds: a low wavering hum)."""
    h = int(hashlib.sha1(path.encode()).hexdigest()[:8], 16)
    fade = "min(1,t/0.005)*min(1,({d}-t)/0.005)".format(d=dur)
    if kind == "bed":
        f = 110 + h % 110
        return "0.035*sin(2*PI*{f}*t)*(0.7+0.3*sin(2*PI*0.5*t))*{fade}".format(f=f, fade=fade)
    f = (220 + h % 220) if kind == "sfx" else (330 + h % 330)
    blip = "0.09*sin(2*PI*1760*t)*lt(t,0.04)"
    return "(0.05*sin(2*PI*{f}*t)+{blip})*{fade}".format(f=f, blip=blip, fade=fade)


def encode(dest, path, kind, dur, force):
    """Writes one clip. Returns (dest, made)."""
    if dest.exists() and not force:
        return dest, False
    dest.parent.mkdir(parents=True, exist_ok=True)
    if kind == "voice":
        rate, args = 48000, OPUS
    else:
        rate, args = RATES.get(path.split("/")[0], 44100), AAC
    tmp = dest.with_name(dest.stem + ".tmp" + dest.suffix)
    src = "aevalsrc=exprs='{e}':s={r}:d={d}:c=mono".format(e=tone(path, kind, dur), r=rate, d=dur)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", src, "-ac", "1", "-ar", str(rate), *args,
                    str(tmp)], check=True)
    tmp.replace(dest)
    return dest, True


def cover(dest, index, force, source=None):
    """Writes a game's cover: [source] (a real cover) at 676x380, else a plain gradient. A real cover is written
    every time (it may have changed since); a gradient only when there's none, or with [force]."""
    if source is not None and source.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name(dest.stem + ".tmp" + dest.suffix)
        if image_size(source) == tuple(int(n) for n in COVER.split("x")):
            shutil.copyfile(source, tmp)
        else:
            w, h = COVER.split("x")
            fit = "scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,crop={w}:{h}".format(w=w, h=h)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-vf", fit, "-frames:v", "1",
                            "-q:v", "2", str(tmp)], check=True)
        tmp.replace(dest)
        return
    if dest.exists() and not force:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    c0 = COLOURS[index % len(COLOURS)]
    c1 = COLOURS[(index + 3) % len(COLOURS)]
    src = "gradients=s={s}:c0=0x{a}:c1=0x{b}:x0=0:y0=0:x1=676:y1=380:nb_colors=2:d=1".format(s=COVER, a=c0, b=c1)
    box = "drawbox=x=48:y=48:w=580:h=284:color=white@0.5:t=10"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", src, "-vf", box, "-frames:v", "1", "-q:v", "4",
                    str(dest)], check=True)


def image_size(path):
    """An image's (width, height), by ffprobe."""
    p = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                        "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    w, h = p.stdout.strip().split(",")[:2]
    return int(w), int(h)


def duration(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
                        str(path)], capture_output=True, text=True)
    return float(p.stdout.strip())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", default=str(ROOT / "build" / "placeholder-content"), help="the content folder to write")
    ap.add_argument("--packs", default=str(ROOT / "build" / "placeholder-packs"),
                    help="where the packs' own clips go, as installed pack folders")
    ap.add_argument("--no-packs", action="store_true", help="skip the packs' clips")
    ap.add_argument("--covers", default=str(WEB_COVERS),
                    help="a folder of real covers, <id>.jpg, used in place of the plain ones (default: the website's)")
    ap.add_argument("--game", help="one game id (default: all)")
    ap.add_argument("--force", action="store_true", help="write every file again")
    ap.add_argument("--verify", action="store_true", help="check every clip's length with ffprobe (within 0.12 s)")
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg isn't installed (brew install ffmpeg)")
    out, packs_out = Path(args.out), Path(args.packs)

    catalog = json.loads((GAMES / "catalog.json").read_text(encoding="utf-8"))["games"]
    jobs = []           # (dest, path, kind, dur)
    covers = []
    for index, game in enumerate(catalog):
        gid = game["id"]
        if args.game and gid != args.game:
            continue
        covers.append((out / gid / "cover.jpg", index))
        if (GAMES / gid / "clips.json").exists():
            clips = nuclear_plays(json.loads((GAMES / gid / "clips.json").read_text(encoding="utf-8")))
            base = {}
        else:
            base = plays(json.loads((GAMES / gid / "map.json").read_text(encoding="utf-8")))
            clips = base
        for path, (dur, kind) in clips.items():
            ext = ".opus" if kind == "voice" else ".m4a"
            jobs.append((out / gid / (path + ext), path, kind, dur or DEFAULT_DUR))
        if args.no_packs:
            continue
        for pack in game.get("packs", []):
            pack_file = GAMES / gid / "packs" / (pack["id"] + ".json")
            pack_map = json.loads(pack_file.read_text(encoding="utf-8"))
            folder = packs_out / pack["id"]
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(pack_file, folder / "pack.json")
            (folder / ".version").write_text(str(pack["version"]), encoding="utf-8")
            for path, (dur, kind) in plays(pack_map).items():
                if path not in base:
                    jobs.append((folder / (path + ".m4a"), path, kind, dur or DEFAULT_DUR))

    made = 0
    seconds = 0.0
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        futures = [pool.submit(encode, dest, path, kind, dur, args.force) for dest, path, kind, dur in jobs]
        for f in cf.as_completed(futures):
            made += f.result()[1]
    real = 0
    for dest, index in covers:
        source = Path(args.covers) / (dest.parent.name + ".jpg")
        cover(dest, index, args.force, source)
        real += source.exists()
    seconds = sum(dur for _, _, _, dur in jobs)
    print("{} clips ({} written, {:.1f} hours of audio) and {} covers ({} from {}) -> {}{}".format(
        len(jobs), made, seconds / 3600, len(covers), real, args.covers, out,
        "" if args.no_packs else ", packs -> {}".format(packs_out)))

    if args.verify:
        with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            got = list(pool.map(lambda j: (j, duration(j[0])), jobs))
        bad = [(j[0], j[3], d) for j, d in got if abs(d - j[3]) > 0.12]
        for dest, want, have in bad[:20]:
            print("  ! {}: wants {:.3f} s, is {:.3f} s".format(dest, want, have))
        print("verified {} clips: {} off by more than 0.12 s".format(len(got), len(bad)))
        if bad:
            sys.exit(1)


if __name__ == "__main__":
    main()
