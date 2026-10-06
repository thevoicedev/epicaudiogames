"""Fetches each game's cover (its Mini Games lobby tile, 676x380) into content/<id>/cover.jpg.

The app shows it on the game list, and a round crop of it in the game screen's talking circle.

Usage (from the repo root): python tools/fetch_art.py
"""
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CDN = "https://x9gq2b7lta.com/en/images/new-covers/"

# Each game's tile in the skill's Images.js (newLobbyIcons). Signal Decoders uses its launch tile, not the
# "COMING SOON!" one.
COVERS = {
    "noodle-rush": "noodle-rush-2.jpg",
    "frootopia": "frootopia-3.jpg",
    "signal-decoders": "alien-invasion.jpg",
}


def main():
    games = {g["id"] for g in json.loads((ROOT / "games" / "catalog.json").read_text(encoding="utf-8"))["games"]}
    for game, name in COVERS.items():
        if game not in games:
            continue
        dest = ROOT / "content" / game / "cover.jpg"
        req = urllib.request.Request(CDN + name, headers={"User-Agent": "epicaudiogames-tools/1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print(f"{game}: {name}, {len(data) // 1024} KB -> {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
