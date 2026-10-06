"""Fetches every clip the maps play into content/<id>/, ready for the app.

For each "play" path in games/<id>/map.json:
  1. download the live clip from the Mini Games CDN (cached in tools/cache/cdn/), the version the Alexa skill plays;
  2. if the local radio-play pipeline in all-minigames-sites still has the lossless master that made exactly that
     file (its delivery MP3 is byte-for-byte the CDN one), encode from the master: better sound at the same size;
  3. otherwise keep the CDN MP3 as it is, rather than encode a lossy file a second time.

Masters become mono AAC (.m4a, 48 kbps) by default, or Ogg Opus (.opus) with --codec opus. Nothing in
all-minigames-sites is written. Clips that already exist in content/ are skipped unless --force.

Usage (from the repo root): python tools/fetch_audio.py [--game noodle-rush] [--codec aac|opus] [--force]
"""
import argparse
import concurrent.futures as cf
import json
import os
import shutil
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MINI = Path(os.environ.get("MINIGAMES_DIR") or ROOT.parent / "all-minigames-sites")
CDN = "https://x9gq2b7lta.com/"
CACHE = ROOT / "tools" / "cache" / "cdn"
CONTENT = ROOT / "content"

# Each map's source folder in all-minigames-sites/alexa/tools (its game.json has the CDN prefix).
SOURCES = {"noodle-rush": "noodle-rush", "frootopia": "frootopia", "signal-decoders": "alien-invasion"}
CODECS = {
    "aac": (".m4a", ["-c:a", "aac", "-b:a", "48k", "-ar", "32000", "-movflags", "+faststart"]),
    "opus": (".opus", ["-c:a", "libopus", "-b:a", "32k", "-application", "audio", "-ar", "48000"]),
}
EXTS = (".m4a", ".opus", ".mp3")


def plays(game_map):
    """Every clip path the map plays: says, reprompts and else-says."""
    out = set()
    for node in game_map["nodes"].values():
        lists = [node.get("say", [])]
        ask = node.get("ask")
        if ask:
            lists.append(ask.get("reprompt", []))
            if isinstance(ask.get("else"), dict):
                lists.append(ask["else"].get("say", []))
        for steps in lists:
            out.update((s["play"], s["dur"]) for s in steps if "play" in s)
    return sorted(out)


def download(url, dest):
    if dest.exists():
        return dest.read_bytes()
    req = urllib.request.Request(url, headers={"User-Agent": "epicaudiogames-tools/1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    tmp.write_bytes(data)
    tmp.replace(dest)
    return data


def duration(path):
    p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
                        str(path)], capture_output=True, text=True)
    return float(p.stdout.strip())


def fetch(game, tools_dir, prefix, path, dur, codec, force):
    """Returns (path, source, bytes, problem)."""
    ext, args = CODECS[codec]
    existing = [CONTENT / game / f"{path}{e}" for e in EXTS if (CONTENT / game / f"{path}{e}").exists()]
    if existing and not force:
        return path, "kept", existing[0].stat().st_size, None
    for old in existing:
        old.unlink()
    cdn_bytes = download(f"{CDN}{prefix}{path}.mp3", CACHE / game / f"{path}.mp3")
    dist = tools_dir / "out" / "dist" / f"{path}.mp3"
    master = tools_dir / "out" / "mix" / f"{path}.wav"
    out_dir = (CONTENT / game / path).parent
    out_dir.mkdir(parents=True, exist_ok=True)
    problem = None
    if master.exists() and dist.exists() and dist.read_bytes() == cdn_bytes and abs(duration(master) - dur) < 0.02:
        dest = CONTENT / game / f"{path}{ext}"
        tmp = dest.with_name(dest.stem + ".tmp" + ext)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(master), "-ac", "1", *args, str(tmp)], check=True)
        tmp.replace(dest)
        source = "master"
    else:
        dest = CONTENT / game / f"{path}.mp3"
        shutil.copyfile(CACHE / game / f"{path}.mp3", dest)
        source = "cdn"
    got = duration(dest)
    if abs(got - dur) > 0.12:
        problem = f"{path}: the map says {dur:.2f} s, the audio is {got:.2f} s"
    return path, source, dest.stat().st_size, problem


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game", help="one game id (default: all)")
    ap.add_argument("--codec", choices=sorted(CODECS), default="aac")
    ap.add_argument("--force", action="store_true", help="fetch and encode again")
    args = ap.parse_args()
    for game, tools_name in SOURCES.items():
        if args.game and game != args.game:
            continue
        game_map = json.loads((ROOT / "games" / game / "map.json").read_text(encoding="utf-8"))
        tools_dir = MINI / "alexa" / "tools" / tools_name
        prefix = json.loads((tools_dir / "game.json").read_text(encoding="utf-8"))["cdn_prefix"]
        clips = plays(game_map)
        counts, size, problems = {}, 0, []
        with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
            jobs = [pool.submit(fetch, game, tools_dir, prefix, p, d, args.codec, args.force) for p, d in clips]
            for job in cf.as_completed(jobs):
                path, source, nbytes, problem = job.result()
                counts[source] = counts.get(source, 0) + 1
                size += nbytes
                if problem:
                    problems.append(problem)
        detail = ", ".join(f"{n} {k}" for k, n in sorted(counts.items()))
        print(f"{game}: {len(clips)} clips ({detail}), {size / 1e6:.1f} MB -> {(CONTENT / game).relative_to(ROOT)}")
        for problem in sorted(problems):
            print(f"  ! {problem}")


if __name__ == "__main__":
    main()
