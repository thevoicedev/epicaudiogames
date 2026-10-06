"""Removes audio that no map plays from content/<id>/, so the app doesn't ship it.

The builders leave the parts of every pre-mix (a reply, the effect under it) and older renders next to the files
the map uses; the app bundles the whole folder. This keeps only what each game's map refers to (clips and beds,
inside picks and cases too) and the cover. The caches in tools/cache/ keep everything, so a rebuild is quick.

Usage (from the repo root): python tools/prune.py [--game id] [--dry-run]
"""
import argparse
import json
from pathlib import Path

from validate import plays

ROOT = Path(__file__).resolve().parents[1]
KEEP = {"cover.jpg"}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    for path in sorted((ROOT / "games").glob("*/map.json")):
        game = path.parent.name
        if args.game and game != args.game:
            continue
        used = set(plays(json.loads(path.read_text(encoding="utf-8"))))
        folder = ROOT / "content" / game
        gone, freed = 0, 0
        for f in folder.rglob("*"):
            if not f.is_file() or f.name in KEEP:
                continue
            rel = f.relative_to(folder).with_suffix("").as_posix()
            if rel in used:
                continue
            gone += 1
            freed += f.stat().st_size
            if not args.dry_run:
                f.unlink()
        for d in sorted((p for p in folder.rglob("*") if p.is_dir()), key=lambda p: -len(p.parts)):
            if not args.dry_run and not any(d.iterdir()):
                d.rmdir()
        print(f"{game}: {'would remove' if args.dry_run else 'removed'} {gone} files, {freed / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
