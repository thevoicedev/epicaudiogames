"""Where everything lives, and the brand's own settings: brand/brand.json, brand/prompts/<kind>.json, brand/shots.json,
brand/picks.json and brand/alt-text.json.

JSON is written with LF line endings and a final newline whatever the machine (the repo is checked out with LF on
Windows too), and replaced in one step so a crash never leaves half a file.
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "brand"
MASTERS = BRAND / "masters"
CACHE = ROOT / "tools" / "cache" / "art"
BUILD = ROOT / "build" / "art"
MINI = Path(os.environ.get("MINIGAMES_DIR") or ROOT.parent / "all-minigames-sites")


def read_json(path, default=None):
    path = Path(path)
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data, compact=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":")) if compact \
        else json.dumps(data, ensure_ascii=False, indent=2)
    write_text(path, text + "\n")


def write_text(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def write_bytes(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def now():
    """The time, in UTC, to the second (for meta.json and the ledger)."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def rel(path):
    """A path as it's shown: relative to the repo when it's inside it, with forward slashes."""
    path = Path(path).resolve()
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


_brand = None


def brand():
    global _brand
    if _brand is None:
        _brand = read_json(BRAND / "brand.json")
        if _brand is None:
            raise SystemExit("brand/brand.json is missing")
    return _brand


def prompts(kind):
    data = read_json(BRAND / "prompts" / f"{kind}.json")
    if data is None:
        raise SystemExit(f"brand/prompts/{kind}.json is missing")
    return data


def shots_spec():
    return read_json(BRAND / "shots.json")


def picks():
    return read_json(BRAND / "picks.json", {"icon": None, "feature": None})


def save_picks(data):
    write_json(BRAND / "picks.json", data)


def alt_text():
    return read_json(BRAND / "alt-text.json", {})


def save_alt_text(data):
    write_json(BRAND / "alt-text.json", data)


def colour(name_or_hex):
    """A palette name ("gold") or "#RRGGBB" as an (r, g, b) tuple."""
    value = brand()["palette"].get(name_or_hex, name_or_hex)
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"not a colour: {name_or_hex!r}")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def font_path(weight):
    """The Atkinson Hyperlegible Next file for a weight (regular, bold, extrabold), or None while it's missing."""
    path = ROOT / brand()["fonts"][weight]
    return path if path.exists() else None
