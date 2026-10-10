"""make_art.py check: the brand files, the cache and its ledger, the picks, and every exported image against the
platforms' and stores' rules (the ones the fastlane check lanes apply, and more: safe zones, alpha where it must or
mustn't be, the emblem's contrast). Errors exit 1; warnings don't.

With --out it checks a trial export under that folder (export --out writes export.json there, so the trial can be
rendered again and compared pixel for pixel) instead of the repo's app, store and web folders.
"""
import json
import re

import numpy as np
from PIL import Image

from .brand import BRAND, CACHE, MASTERS, ROOT, brand, colour, font_path, picks, prompts, read_json, rel, shots_spec
from .cache import find, index, ledger
from .compose import contrast, luminance

DESIGN_TOKENS = {"navy": "background", "navyRaised": "surface", "gold": "heading", "text": "text",
                 "textMuted": "textMuted", "outline": "outline", "outlineSubtle": "outlineSubtle (decorative)"}
KEY_LIKE = re.compile(r"sk-(proj-)?[A-Za-z0-9_\-]{20,}")
IOS_SIZES = {(1320, 2868), (1290, 2796), (1260, 2736), (1206, 2622), (1179, 2556), (1284, 2778)}


class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def error(self, text):
        self.errors.append(text)
        print(f"  error: {text}")

    def warn(self, text):
        self.warnings.append(text)
        print(f"  warning: {text}")

    def ok(self, text):
        print(f"  ok: {text}")


def png_type(path):
    """A PNG's colour type (2 RGB, 6 RGBA, 4 grey + alpha, 0 grey, 3 palette), or None for anything else."""
    with open(path, "rb") as f:
        head = f.read(26)
    return head[25] if head[:8] == b"\x89PNG\r\n\x1a\n" else None


def _open(path):
    with Image.open(path) as im:
        im.load()
        return im.copy()


def _reach(image):
    """How far the furthest visible pixel is from the image's centre (pixels)."""
    a = np.asarray(image.getchannel("A"))
    h, w = a.shape
    ys, xs = np.nonzero(a > 32)
    return float(np.max(np.hypot(xs + 0.5 - w / 2, ys + 0.5 - h / 2))) if len(xs) else 0.0


# ----- brand -----

def check_brand(r):
    print("brand:")
    design = (ROOT / "docs" / "DESIGN.md").read_text(encoding="utf-8")
    pal = brand()["palette"]
    for name, token in DESIGN_TOKENS.items():
        m = re.search(r"^\| " + re.escape(token) + r" \| (#[0-9A-Fa-f]{6})", design, re.M)
        if not m:
            r.warn(f"docs/DESIGN.md has no {token} row to compare {name} with")
        elif m.group(1).upper() != pal[name].upper():
            r.error(f"brand.json {name} {pal[name]} isn't DESIGN.md's Dark {token} {m.group(1)}")
    m = re.search(r"^\| primary / onPrimary \| (#[0-9A-Fa-f]{6}) / (#[0-9A-Fa-f]{6})", design, re.M)
    if m and (m.group(1).upper() != pal["gold"].upper() or m.group(2).upper() != pal["onGold"].upper()):
        r.error("brand.json gold/onGold aren't DESIGN.md's Dark primary/onPrimary")
    r.ok("the palette matches docs/DESIGN.md's Dark tokens")
    for c in brand()["emblemColours"]:
        ratio = float(contrast(luminance(np.array(colour(c))), luminance(np.array(colour("navy")))))
        (r.ok if ratio >= 3 else r.error)(f"emblem colour {c} on navy: {ratio:.1f}:1 (3:1 at least)")
    missing = [w for w in brand()["fonts"] if font_path(w) is None]
    if missing:
        r.warn(f"fonts not there yet: {', '.join(missing)} (captions and titles can't be set)")
    else:
        r.ok("the three Atkinson Hyperlegible Next fonts are there")
    for kind in ("icon", "feature"):
        p = prompts(kind)
        if "{motif}" not in p["base"]:
            r.error(f"brand/prompts/{kind}.json: base has no {{motif}}")
        ids = [m["id"] for m in p["motifs"]]
        if len(ids) != len(set(ids)):
            r.error(f"brand/prompts/{kind}.json: motif ids repeat")
        for m in p["motifs"]:
            if not all(m.get(k) for k in ("id", "name", "prompt", "alt")):
                r.error(f"brand/prompts/{kind}.json: motif {m.get('id')} needs id, name, prompt and alt")
    s = shots_spec()
    for shot in s["shots"]:
        if shot["caption"].count("*") % 2:
            r.error(f"brand/shots.json: {shot['name']}'s caption has an odd number of stars")
    r.ok("prompts and shots.json are well formed")


# ----- cache -----

def check_cache(r):
    print("cache:")
    entries = ledger()
    for e in entries:
        if find(e["key"]) is None:
            r.error(f"ledger line for {e['key'][:12]} has no cache folder")
    total = sum(e.get("cost_usd") or 0 for e in entries)
    r.ok(f"{len(entries)} paid calls in the ledger, ${total:.3f} in all")
    for cid, c in index()["concepts"].items():
        entry = find(c["key"])
        if entry is None:
            r.error(f"{cid}: its image ({c['key'][:12]}) isn't in the cache")
            continue
        try:
            entry.path(c.get("image", 0))
        except FileNotFoundError:
            r.error(f"{cid}: its image file is missing")
        layer = c.get("layer") or {}
        if layer.get("key") and find(layer["key"]) is None:
            r.error(f"{cid}: its layer ({layer['key'][:12]}) isn't in the cache")
        if layer.get("method") == "vector redraw needed":
            r.warn(f"{cid}: needs a vector redraw before it can be exported")
    r.ok(f"{len(index()['concepts'])} concepts indexed, every one in the cache")
    for d in CACHE.glob("*/*"):
        if d.is_dir() and not (d / "meta.json").exists():
            r.warn(f"{rel(d)}: an unfinished cache folder (no meta.json)")
    leaks = []
    for folder in (CACHE, BRAND):
        for path in folder.rglob("*"):
            if path.is_file() and path.suffix in (".json", ".jsonl", ".txt", ".md", ".html"):
                if KEY_LIKE.search(path.read_text(encoding="utf-8", errors="replace")):
                    leaks.append(rel(path))
    for path in leaks:
        r.error(f"{path} has something that looks like an API key in it")
    if not leaks:
        r.ok("no API key anywhere in tools/cache/art/ or brand/")


def check_picks(r):
    print("picks:")
    p = picks()
    if not p.get("icon"):
        r.ok("no icon picked yet (gate 3)")
    else:
        emblem = MASTERS / "icon-emblem.png"
        if not emblem.exists() or not (MASTERS / "icon-concept.webp").exists():
            r.error("the icon is picked but brand/masters/ doesn't have icon-emblem.png and icon-concept.webp")
        else:
            im = _open(emblem)
            if im.mode != "RGBA" or not np.asarray(im.getchannel("A")).any():
                r.error("brand/masters/icon-emblem.png isn't an emblem on transparent")
            else:
                r.ok(f"icon {p['icon']['id']} picked; its masters are there")
    if p.get("feature"):
        if not (MASTERS / "feature-art.webp").exists():
            r.error("the feature art is picked but brand/masters/feature-art.webp is missing")
        else:
            r.ok(f"feature art {p['feature']['id']} picked")


# ----- exports -----

def check_exports(r, root, trial):
    from .icons import IOS_ASSETS, PLAY, RES, WEB, emblem_master, feature_art, render, same
    print(f"exports ({rel(root)}):")
    made = read_json(root / "export.json") if trial else None
    if not trial and not picks().get("icon"):
        r.ok("no icon picked yet: the apps still have the old icon, so there's nothing of ours to check")
        return
    if trial and not made:
        r.error(f"{rel(root)} has no export.json: not a make_art.py export --out folder")
        return
    what = made["what"] if made else "all"
    if what in ("icons", "all"):
        _check_ios(r, root / IOS_ASSETS)
        _check_android(r, root / RES)
    if what in ("store", "all"):
        _check_play(r, root / PLAY)
    if what in ("web", "all"):
        _check_web(r, root / WEB)
    emblem = emblem_master(made.get("icon") if made else None)
    art = feature_art(made.get("feature") if made else None)
    files = render(what, emblem, art)
    bad = [p for p, spec in files.items() if not same(root / p, spec)]
    for p in bad:
        r.error(f"{p} isn't what a fresh export makes (export again, or export --check)")
    if not bad:
        r.ok(f"all {len(files)} files are exactly what a fresh export makes (deterministic)")
    if not trial:
        manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
        if 'android:roundIcon="@mipmap/ic_launcher_round"' not in manifest:
            r.warn('AndroidManifest.xml: android:roundIcon should be "@mipmap/ic_launcher_round"')


def _check_ios(r, assets):
    folder = assets / "AppIcon.appiconset"
    icon = folder / "AppIcon.png"
    if not icon.exists():
        r.error(f"{rel(icon)} is missing")
        return
    im = _open(icon)
    if im.size != (1024, 1024) or png_type(icon) != 2:
        r.error(f"{rel(icon)} must be 1024x1024 RGB without alpha (App Store Connect refuses alpha: ITMS-90717); "
                f"it's {im.size[0]}x{im.size[1]}, PNG colour type {png_type(icon)}")
    else:
        r.ok("AppIcon.png: 1024x1024, RGB, no alpha")
    for name, grey_only in (("AppIcon-Dark.png", False), ("AppIcon-Tinted.png", True)):
        path = folder / name
        if not path.exists():
            r.warn(f"{rel(path)} is missing (iOS 18 dark/tinted icon)")
            continue
        im = _open(path)
        a = np.asarray(im.convert("RGBA"))
        if im.size != (1024, 1024) or im.mode != "RGBA" or a[0, 0, 3] or a[-1, -1, 3]:
            r.error(f"{rel(path)} must be 1024x1024 RGBA with a transparent background")
        elif grey_only and not (np.array_equal(a[..., 0], a[..., 1]) and np.array_equal(a[..., 1], a[..., 2])):
            r.error(f"{rel(path)} must be grey")
        else:
            r.ok(f"{name}: 1024x1024, emblem on transparent" + (", grey" if grey_only else ""))
    contents = read_json(folder / "Contents.json") or {}
    names = {i.get("filename") for i in contents.get("images", [])}
    if not {"AppIcon.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"} <= names:
        r.error(f"{rel(folder / 'Contents.json')} doesn't list the three icons")
    launch = assets / "LaunchLogo.imageset"
    for s in brand()["icon"]["launch"]["scales"]:
        path = launch / f"LaunchLogo@{s}x.png"
        want = brand()["icon"]["launch"]["pt"] * s
        if not path.exists() or _open(path).size != (want, want):
            r.error(f"{rel(path)} should be {want}x{want}")
    r.ok("LaunchLogo.imageset: 160 pt at @2x and @3x")


def _check_android(r, res):
    a = brand()["icon"]["android"]
    for name, d in a["densities"].items():
        folder = res / f"mipmap-{name}"
        px = round(a["canvasDp"] * d)
        fg = folder / "ic_launcher_foreground.png"
        if not fg.exists():
            r.error(f"{rel(fg)} is missing")
            continue
        im = _open(fg)
        if im.size != (px, px) or im.mode != "RGBA":
            r.error(f"{rel(fg)} should be {px}x{px} RGBA")
        reach = _reach(im)
        if reach > 33 * d + 0.5:
            r.error(f"{rel(fg)}: the emblem reaches {reach / d:.1f} dp from the centre, outside the 66 dp safe zone")
        mono = _open(folder / "ic_launcher_monochrome.png")
        m = np.asarray(mono.convert("RGBA"))
        if (m[..., :3][m[..., 3] > 0] != 255).any():
            r.error(f"{rel(folder / 'ic_launcher_monochrome.png')} must be white on transparent")
        if _reach(mono) > 33 * d + 0.5:
            r.error(f"{rel(folder / 'ic_launcher_monochrome.png')} reaches outside the 66 dp safe zone")
        bg = _open(folder / "ic_launcher_background.png")
        if bg.size != (px, px):
            r.error(f"{rel(folder / 'ic_launcher_background.png')} should be {px}x{px}")
        for legacy in ("ic_launcher.png", "ic_launcher_round.png"):
            im = _open(folder / legacy)
            lpx = round(brand()["icon"]["legacy"]["sizeDp"] * d)
            if im.size != (lpx, lpx) or im.mode != "RGBA" or np.asarray(im)[0, 0, 3]:
                r.error(f"{rel(folder / legacy)} should be {lpx}x{lpx} RGBA with transparent corners")
        sp = res / f"drawable-{name}" / "splash_emblem.png"
        im = _open(sp)
        spx = round(brand()["icon"]["splash"]["canvasDp"] * d)
        if im.size != (spx, spx) or _reach(im) > 96 * d + 0.5:
            r.error(f"{rel(sp)} should be {spx}x{spx} with the emblem inside the 192 dp circle")
    r.ok("adaptive layers in every density, emblem and silhouette inside the 66 dp safe zone, legacy and splash")
    for xml in ("ic_launcher.xml", "ic_launcher_round.xml"):
        text = (res / "mipmap-anydpi-v26" / xml).read_text(encoding="utf-8")
        for layer in ("background", "foreground", "monochrome"):
            if f"<{layer} " not in text:
                r.error(f"{rel(res / 'mipmap-anydpi-v26' / xml)} has no <{layer}>")
    colours = (res / "values" / "colors.xml").read_text(encoding="utf-8")
    navy = "#FF" + "".join(f"{v:02X}" for v in colour("navy"))
    if f'<color name="ic_launcher_background">{navy}</color>' not in colours:
        r.error(f"{rel(res / 'values' / 'colors.xml')}: ic_launcher_background should be {navy}")
    r.ok("adaptive icon XML (background, foreground, monochrome) and the navy launcher background colour")


def _check_play(r, play):
    icon = play / "icon.png"
    im = _open(icon)
    if im.size != (512, 512) or png_type(icon) != 6 or icon.stat().st_size > 1024 * 1024:
        r.error(f"{rel(icon)} must be 512x512, a 32-bit PNG (with alpha, as the Fastfile checks), under 1 MB")
    elif np.asarray(im)[..., 3].min() < 255:
        r.warn(f"{rel(icon)} has see-through pixels; Play wants the square filled")
    else:
        r.ok("Play icon.png: 512x512, 32-bit, opaque, full bleed, under 1 MB")
    fg = play / "featureGraphic.png"
    im = _open(fg)
    if im.size != (1024, 500) or png_type(fg) in (4, 6) or fg.stat().st_size > 15 * 1024 * 1024:
        r.error(f"{rel(fg)} must be 1024x500 without alpha, under 15 MB")
    else:
        r.ok("Play featureGraphic.png: 1024x500, no alpha")


def _check_web(r, web):
    with Image.open(web / "favicon.ico") as ico:
        sizes = {s[0] for s in ico.ico.sizes()}
    if not {16, 32, 48} <= sizes:
        r.error(f"{rel(web / 'favicon.ico')} should hold 16, 32 and 48 px (it has {sorted(sizes)})")
    for name, size, mode in (("apple-touch-icon.png", 180, "RGB"), ("icon-192.png", 192, "RGB"),
                             ("icon-512.png", 512, "RGB"), ("icon-maskable-512.png", 512, "RGB"),
                             ("emblem.png", brand()["icon"]["web"]["emblemPx"], "RGBA")):
        im = _open(web / name)
        if im.size != (size, size) or im.mode != mode:
            r.error(f"{rel(web / name)} should be {size}x{size} {mode}")
    og = _open(web / "og-v2.png")
    if og.size != (1200, 630) or og.mode != "RGB":
        r.error(f"{rel(web / 'og-v2.png')} should be 1200x630 RGB")
    manifest = json.loads((web / "manifest.webmanifest").read_text(encoding="utf-8"))
    for icon in manifest.get("icons", []):
        if not (web / icon["src"].lstrip("/")).exists():
            r.error(f"manifest.webmanifest lists {icon['src']}, which isn't there")
    r.ok("website icons, favicon (16, 32, 48), social image and web manifest")


# ----- screenshots -----

def check_shots(r, root):
    spec = shots_spec()
    print("screenshots:")
    android = root / spec["android"]["out"]
    shots = sorted(android.glob("*.png")) if android.exists() else []
    if shots:
        if not 2 <= len(shots) <= 8:
            r.error(f"{rel(android)}: {len(shots)} screenshots; Play takes 2 to 8")
        for p in shots:
            im = _open(p)
            if png_type(p) in (4, 6):
                r.error(f"{rel(p)} has alpha; Play wants screenshots without")
            if im.size[1] * 9 != im.size[0] * 16 or im.size[0] < 1080:
                r.warn(f"{rel(p)} is {im.size[0]}x{im.size[1]}, not 9:16 of at least 1080x1920")
        r.ok(f"{len(shots)} Play screenshots")
    ios = root / spec["ios"]["out"]
    shots = sorted(ios.glob("*.png")) if ios.exists() else []
    if shots:
        by = {}
        for p in shots:
            im = _open(p)
            if im.size not in IOS_SIZES:
                r.error(f"{rel(p)} is {im.size[0]}x{im.size[1]}: not an App Store iPhone size")
            if png_type(p) in (4, 6):
                r.error(f"{rel(p)} has alpha; the App Store refuses it")
            by.setdefault(im.size, []).append(p)
        for size, files in by.items():
            if len(files) > 10:
                r.error(f"{len(files)} screenshots at {size[0]}x{size[1]}; at most 10")
        r.ok(f"{len(shots)} App Store screenshots at {', '.join(f'{w}x{h}' for w, h in sorted(by))}")


def run_check(out=None):
    from .icons import out_root
    r = Report()
    root = out_root(out)
    check_brand(r)
    check_cache(r)
    check_picks(r)
    check_exports(r, root, trial=bool(out))
    check_shots(r, root)
    print(f"{len(r.errors)} error{'s' if len(r.errors) != 1 else ''}, {len(r.warnings)} "
          f"warning{'s' if len(r.warnings) != 1 else ''}")
    return 1 if r.errors else 0
