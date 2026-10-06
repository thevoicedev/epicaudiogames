"""Makes a pack: what a full build of a game has beyond its free map, and the audio for it.

A game's builder with --build build/packs (all of Alien Customs' 15 levels, all 50 Werewolf stories) writes the
whole game to build/packs/<game>/. This keeps what differs from the free map, games/<game>/map.json:

- the pack's map, games/<game>/packs/<pack>.json (in git, so the tests can play the free map with it): the nodes that
  are new or different, and the variables, keep and speakers that are new (docs/MAP_FORMAT.md, Packs);
- its zip, dist/packs/<pack>-<version>.zip, for the pack server: pack.json and the audio those nodes play that the
  free game doesn't ship;
- its entry in games/catalog.json: title, description, Play product id, version, size and checksum.

Usage (from the repo root):
  python tools/make_pack.py alien-customs --id alien-customs-levels --title "10 more levels" \\
      --description "..." --product alien_customs_levels [--version 1]
"""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

from validate import plays

ROOT = Path(__file__).resolve().parents[1]
EXTS = (".m4a", ".mp3", ".opus")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("game")
    ap.add_argument("--id", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--description", required=True)
    ap.add_argument("--product", required=True, help="the Google Play in-app product id")
    ap.add_argument("--version", type=int, default=1)
    ap.add_argument("--build", default="build/packs")
    args = ap.parse_args()

    base_file = ROOT / "games" / args.game / "map.json"
    build = ROOT / args.build / args.game
    base = json.loads(base_file.read_text(encoding="utf-8"))
    full = json.loads((build / "map.json").read_text(encoding="utf-8"))
    lost = sorted(set(base["nodes"]) - set(full["nodes"]))
    if lost:
        raise SystemExit(f"the full build has no {lost[:5]}...: is it a build of the same game?")

    pack = {
        "format": 1, "game": args.game, "id": args.id, "version": args.version,
        "title": args.title, "description": args.description, "product": args.product,
        "vars": {k: v for k, v in full["vars"].items() if k not in base["vars"]},
        "keep": [k for k in full.get("keep", []) if k not in base.get("keep", [])],
        "who": {k: v for k, v in full["who"].items() if k not in base["who"]},
        "nodes": {k: v for k, v in full["nodes"].items() if base["nodes"].get(k) != v},
    }

    # The audio: what the pack's nodes play that the free game doesn't ship.
    need = sorted(set(plays(pack)) - set(plays(base)))
    files = []
    for rel in need:
        found = next((build / "content" / (rel + ext) for ext in EXTS if (build / "content" / (rel + ext)).exists()),
                     None)
        if found is None:
            raise SystemExit(f"{rel}: not in {build / 'content'}")
        files.append((rel + found.suffix, found))

    out_map = ROOT / "games" / args.game / "packs" / f"{args.id}.json"
    out_map.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(pack, indent=1, ensure_ascii=False) + "\n"
    out_map.write_text(text, encoding="utf-8")

    out_zip = ROOT / "dist" / "packs" / f"{args.id}-{args.version}.zip"
    out_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_STORED) as z:   # audio doesn't compress further
        z.writestr("pack.json", text)
        for name, path in files:
            z.write(path, name)
    data = out_zip.read_bytes()
    entry = {"id": args.id, "title": args.title, "description": args.description, "product": args.product,
             "version": args.version, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    catalog_file = ROOT / "games" / "catalog.json"
    catalog = json.loads(catalog_file.read_text(encoding="utf-8"))
    game = next(g for g in catalog["games"] if g["id"] == args.game)
    game["packs"] = [p for p in game.get("packs", []) if p["id"] != args.id] + [entry]
    catalog_file.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"{args.id}: {len(pack['nodes'])} nodes, {len(files)} audio files, {len(data) / 1e6:.1f} MB "
          f"-> {out_map.relative_to(ROOT)}, {out_zip.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
