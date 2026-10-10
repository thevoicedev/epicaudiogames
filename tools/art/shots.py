"""Store screenshots, framed: each raw capture (an honest screenshot of the app, from the emulator or the simulator)
on the brand background, scaled down with rounded corners and a thin outline, under its caption in Atkinson
Hyperlegible Next Bold (the *starred* words gold, the rest white: both at least 7:1 on the navy). brand/shots.json
holds the captions and one layout per size; captions are drafts until the owner approves them (gate 4).

  Android  build/store-shots/android/raw/<name>.png -> android/fastlane/metadata/android/en-US/images/
           phoneScreenshots/<name>.png at 1080x1920 (size "phone": Play's 9:16; the emulator's 20:9 captures break
           Play's 2:1 limit). The tablets' captures (tools/store_shots.py android puts them in raw/tablet7/,
           raw/tablet10/ and raw/tablet10-land/) -> sevenInchScreenshots/ at 1080x1920 ("7in") and
           tenInchScreenshots/ at 1440x2560 ("10in") and 2560x1440 ("10in-land", named <name>_landscape.png).
           A Wear OS capture (raw/wear/*.png, "wear") goes to wearScreenshots/ as it is: square, no caption, no frame
           (Play wants the watch's screen alone)
  iOS      build/store-shots/ios/raw/<name>.png -> ios/fastlane/screenshots/en-US/<name>_<w>x<h>.png at 1320x2868
           ("6.9") and 1206x2622 ("6.3"); the 13" iPad's captures (raw/ipad13/) at 2064x2752 ("13"); a raw
           iap_<product>.png is copied as it is to ios/fastlane/iap_review/

--sizes picks the sizes (make_art.py shots android --sizes phone,7in,10in,10in-land); sizes the platform doesn't have
are left out, and with none of its own the platform's "default" ones are made (Android: phone; iOS: 6.9 and 6.3).
A shot whose caption makes a claim ("Works with VoiceOver") is only framed when --claims names it, after the
real-device screen-reader test. PNGs that were in a store folder before and weren't made now are listed; --out
writes a trial anywhere else.
"""
import io
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

from .brand import ROOT, colour, rel, shots_spec, write_bytes
from .compose import background
from .text import draw_lines, face, fit, guard

_backgrounds = {}


def _background(size):
    """The brand background at a size, made once a run (it takes seconds at tablet sizes)."""
    if size not in _backgrounds:
        _backgrounds[size] = background(size)
    return _backgrounds[size]


def _png(image):
    """PNG bytes, RGB, without metadata. Level 6: on the background's noise level 9 takes over ten times as long
    (about 30 s for a 1080x1920 shot) for files under a tenth smaller."""
    buf = io.BytesIO()
    image.convert("RGB").save(buf, "PNG", compress_level=6)
    return buf.getvalue()


def frame(raw, caption, layout, style):
    """One framed screenshot (RGB)."""
    w, h = layout["size"]
    canvas = _background((w, h)).convert("RGBA")
    band = layout["band"]
    margin = round(w * 0.06)
    f = face(style["weight"])
    size, lines = fit(f, caption, w - 2 * margin, layout["caption"], layout["captionMin"], style["lines"])
    box = (margin, round(band * 0.08), w - margin, band)
    guard(canvas, box, [style["colour"], style["key"]])
    draw_lines(canvas, f, lines, size, box, colour(style["colour"]), key=colour(style["key"]), leading=1.18)
    shot = raw.convert("RGB")
    top = layout["screenTop"]
    bottom = max(16, round(min(w, h) * 0.022))     # the margin under the screen
    room = h - top - bottom
    # screenScale of the width, unless the capture is taller than that leaves room for (a 20:9 phone, a tablet):
    # then it fits the height.
    scale = min(w * layout["screenScale"] / shot.size[0], room / shot.size[1])
    sw, sh = round(shot.size[0] * scale), round(shot.size[1] * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x = (w - sw) // 2
    y = top + (room - sh) // 2 if layout.get("screenAlign") == "center" else top
    radius = layout["radius"]
    line = layout["outline"]
    edge = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((x - line, y - line, x + sw + line - 1, y + sh + line - 1),
                                           radius + line, fill=colour(style["outlineColour"]) + (255,))
    canvas.alpha_composite(edge)
    canvas.paste(shot, (x, y), _corner_mask((sw, sh), radius))
    return canvas.convert("RGB")


def plain(raw, layout):
    """A capture as it is (RGB), for stores that want the screen alone (Wear OS): checked, never framed."""
    image = raw.convert("RGB")
    w, h = image.size
    least = layout.get("minSide", 0)
    if layout.get("square") and w != h:
        raise ValueError(f"is {w}x{h}; this size wants a square")
    if min(w, h) < least:
        raise ValueError(f"is {w}x{h}; this size wants at least {least}x{least}")
    return image


def _corner_mask(size, radius):
    """A rounded-rectangle mask with corners of `radius` pixels (supersampled 4x)."""
    w, h = size
    big = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), radius * 4, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def chosen_sizes(platform, sizes):
    """The size names to make, in brand/shots.json's order: the asked-for ones this platform has, else its default."""
    p = shots_spec()[platform]
    asked = [s for s in (sizes or ()) if s]
    known = [s for s in p["sizes"] if s in asked]
    unknown = [s for s in asked if s not in p["sizes"]]
    if known and unknown:
        print(f"not {platform} sizes in brand/shots.json, left out: {', '.join(unknown)}")
    return known or list(p.get("default") or p["sizes"])


def raw_folder(platform, layout, raw_dir=None):
    """Where a size's raw captures are: the platform's raw folder (or --raw), or its rawDir subfolder of it."""
    p = shots_spec()[platform]
    root = Path(raw_dir) if raw_dir else Path(p["raw"])
    if not root.is_absolute():
        root = ROOT / root
    return root / layout["rawDir"] if layout.get("rawDir") else root


def out_name(platform, name, layout, image_size):
    """A framed shot's file name: Android <name><suffix>.png; iOS <name><suffix>_<w>x<h>.png (deliver reads the
    display from the size, and two sizes share the folder)."""
    suffix = layout.get("suffix", "")
    if platform == "android":
        return f"{name}{suffix}.png"
    w, h = image_size
    return f"{name}{suffix}_{w}x{h}.png"


def run_shots(platform, raw_dir=None, claims=(), sizes=("6.9", "6.3"), out=None, replace=False):
    from .icons import out_root
    spec = shots_spec()
    p = spec[platform]
    root = out_root(out)
    style = spec["caption"]
    names = chosen_sizes(platform, sizes)
    made, missing, problems = [], {}, []
    dests = {}
    for size_name in names:
        layout = p["sizes"][size_name]
        raw = raw_folder(platform, layout, raw_dir)
        dest = root / layout.get("out", p["out"])
        dests.setdefault(dest, []).append(size_name)
        if layout.get("plain"):
            count = 0
            for src in sorted(raw.glob("*.png")) if raw.exists() else []:
                with Image.open(src) as im:
                    im.load()
                    capture = im.copy()
                try:
                    image = plain(capture, layout)
                except ValueError as e:
                    problems.append(f"{rel(src)} {e}")
                    continue
                file = dest / out_name(platform, src.stem, layout, image.size)
                write_bytes(file, _png(image))
                made.append(file)
                count += 1
            if not count:
                missing[size_name] = (raw, [])
            continue
        for shot in spec["shots"]:
            if shot.get("platform", platform) != platform or (shot.get("claim") and shot["claim"] not in claims):
                continue
            src = next((raw / f"{shot['name']}{ext}" for ext in (".png", ".jpg") if (raw / f"{shot['name']}{ext}")
                        .exists()), None)
            if src is None:
                missing.setdefault(size_name, (raw, []))[1].append(shot["name"])
                continue
            with Image.open(src) as im:
                im.load()
                capture = im.convert("RGB")
            image = frame(capture, shot["caption"], layout, style)
            file = dest / out_name(platform, shot["name"], layout, layout["size"])
            write_bytes(file, _png(image))
            made.append(file)
    if platform == "ios":
        raw = raw_folder(platform, {}, raw_dir)
        for src in sorted(raw.glob("iap_*.png")):
            target = root / p["iapOut"] / (src.name[len("iap_"):])
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, target)
            made.append(target)
    for f in made:
        print(f"  {rel(f)}")
    for size_name, (raw, shots) in missing.items():
        if shots:
            print(f"{size_name}: no raw capture for: {', '.join(shots)} (looked in {rel(raw)})")
        else:
            print(f"{size_name}: no raw captures in {rel(raw)}")
    for text in problems:
        print(f"not used: {text}")
    for dest, made_here in dests.items():
        # Files another size (not made this time) writes into the same folder aren't old: 10in and 10in-land share
        # tenInchScreenshots/, iOS's sizes share screenshots/en-US/.
        others = [s for s, layout in p["sizes"].items() if s not in made_here and
                  root / layout.get("out", p["out"]) == dest]
        keep = set()
        for s in others:
            layout = p["sizes"][s]
            if layout.get("plain"):
                keep |= set(dest.glob("*.png")) if dest.exists() else set()
                continue
            for shot in spec["shots"]:
                keep.add(dest / out_name(platform, shot["name"], layout, layout["size"]))
        stale = sorted(set(dest.glob("*.png")) - set(made) - keep) if dest.exists() else []
        if stale and replace:
            for f in stale:
                f.unlink()
            print(f"removed {len(stale)} old screenshot{'s' if len(stale) != 1 else ''} from {rel(dest)}")
        elif stale:
            print(f"{len(stale)} other screenshot{'s' if len(stale) != 1 else ''} in {rel(dest)} would be uploaded "
                  f"too (--replace removes them): {', '.join(f.name for f in stale)}")
        count = len(list(dest.glob("*.png"))) if dest.exists() else 0
        if platform == "android" and count > 8:
            print(f"warning: {count} screenshots in {rel(dest)}; Play takes 8 per device type (capture fewer scenes "
                  f"for it: brand/scenes.json)")
    print(f"{len(made)} file{'s' if len(made) != 1 else ''} written")
    return made
