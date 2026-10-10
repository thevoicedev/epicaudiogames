"""Every icon and store/web image, cut from the picked emblem (and the picked feature art, when there is one):
deterministic and offline, so the same picks give the same pixels here and on the Mac. PNGs are written without
metadata. `export --check` renders everything again in memory and compares pixels (not bytes, which depend on the
machine's zlib) with the files on disk.

Where each file goes (under the repo, or under --out for a trial that leaves the apps alone):
  ios/EpicAudioGames/Resources/Assets.xcassets/AppIcon.appiconset/   AppIcon.png (1024, RGB, no alpha),
      AppIcon-Dark.png (the emblem on transparent), AppIcon-Tinted.png (the emblem in grey on transparent), Contents.json
  ios/EpicAudioGames/Resources/Assets.xcassets/LaunchLogo.imageset/  the emblem at 160 pt (@2x, @3x), Contents.json
  android/app/src/main/res/mipmap-<density>/   ic_launcher_foreground, _background and _monochrome (108 dp layers),
      ic_launcher and ic_launcher_round (48 dp, for API 24-25)
  android/app/src/main/res/mipmap-anydpi-v26/  ic_launcher.xml, ic_launcher_round.xml (adaptive, with monochrome)
  android/app/src/main/res/drawable-<density>/splash_emblem.png    the emblem on a 288 dp canvas, for the splash
  android/app/src/main/res/values/colors.xml   ic_launcher_background set to navy (the splash icon's backdrop)
  android/fastlane/metadata/android/en-US/images/   icon.png (512, 32-bit), featureGraphic.png (1024x500, no alpha)
  web/public/   favicon.ico (16, 32, 48), apple-touch-icon.png (180), icon-192.png, icon-512.png,
      icon-maskable-512.png, emblem.png (256, for the header), og-v2.png (1200x630), manifest.webmanifest
"""
import io
import json
import re
import shutil
from datetime import date
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .brand import MASTERS, ROOT, alt_text, brand, colour, now, picks, prompts, rel, save_alt_text, save_picks, \
    write_bytes, write_json
from .cache import Entry, concept
from .compose import background, masked, on, place, rounded, superellipse, trimmed

IOS_ASSETS = "ios/EpicAudioGames/Resources/Assets.xcassets"
RES = "android/app/src/main/res"
PLAY = "android/fastlane/metadata/android/en-US/images"
WEB = "web/public"
OLD = [f"{RES}/mipmap/ic_launcher.xml"]          # the old vector icon's layer-list, replaced by the PNGs


# ----- Where the art comes from -----

def emblem_master(icon=None):
    """The emblem every icon is cut from (RGBA): a concept's layer for a trial (--icon), else the picked one."""
    if icon:
        from .layers import emblem_of
        layer = emblem_of(icon)
        if layer is None:
            raise SystemExit(f"{icon} has no layer yet: make_art.py layers icon {icon}")
        return layer
    path = MASTERS / "icon-emblem.png"
    if not picks().get("icon") or not path.exists():
        raise SystemExit("No icon picked yet (make_art.py pick icon ID), or use --icon ID with --out for a trial.")
    with Image.open(path) as im:
        return im.convert("RGBA")


def feature_art(feature=None):
    """The feature graphic's background art (RGB), or None to use the brand background."""
    if feature:
        c = concept(feature)
        return Entry(c["key"]).image(c.get("image", 0)).convert("RGB")
    path = MASTERS / "feature-art.webp"
    if picks().get("feature") and path.exists():
        with Image.open(path) as im:
            return im.convert("RGB")
    return None


# ----- The pieces -----

def tile(emblem, size, share, radius_share=None):
    """The emblem on the brand background, full bleed (RGBA, opaque): share is its longer side over the tile's,
    radius_share (if given) the furthest any of it may reach from the centre."""
    layer, _ = place(trimmed(emblem), (size, size), share * size, radius_share * size if radius_share else None)
    return on(background((size, size)), layer)


def silhouette(emblem):
    """The emblem in one colour (Android's themed icon, a monochrome layer): alpha at least 0.5, with every part that
    sits inside a part of another colour cut out of it (gold bars on a white speech bubble become holes in the
    bubble, instead of vanishing into it), closed and opened (small gaps and burrs smoothed), specks under 0.2% of it
    removed. L mode, at the emblem's own size."""
    from .compose import _dilate
    from .layers import components, emblem_colours, specks_removed
    arr = np.asarray(emblem.convert("RGBA"), dtype=np.float64)
    solid = arr[..., 3] >= 128
    palette = np.stack(emblem_colours())
    nearest = np.argmin(np.stack([np.linalg.norm(arr[..., :3] - c, axis=2) for c in palette]), axis=0)
    holes = np.zeros(solid.shape, dtype=bool)
    ring_width = max(2, round(0.012 * max(solid.shape)))
    for k in range(len(palette)):
        mine = solid & (nearest == k)
        others = solid & (nearest != k)
        for blob in components(mine):
            part = np.zeros(solid.size, dtype=bool)
            part[blob] = True
            part = part.reshape(solid.shape)
            ys, xs = np.nonzero(part)
            y0, y1 = max(0, ys.min() - ring_width - 1), min(solid.shape[0], ys.max() + ring_width + 2)
            x0, x1 = max(0, xs.min() - ring_width - 1), min(solid.shape[1], xs.max() + ring_width + 2)
            local = part[y0:y1, x0:x1]
            ring = _dilate(local, ring_width) & ~local
            if ring.any() and others[y0:y1, x0:x1][ring].mean() > 0.85:
                holes[y0:y1, x0:x1] |= local
    m = Image.fromarray(((solid & ~holes) * 255).astype(np.uint8), "L")
    m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))        # close
    m = m.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))        # open
    a = specks_removed(np.asarray(m, dtype=np.float64) / 255.0)
    return Image.fromarray(np.round(a * 255).astype(np.uint8), "L")


def tinted(layer):
    """The iOS tinted icon's grey emblem: its luminance, stretched so the emblem's darkest colour sits at 40% and its
    lightest at 100% (in linear light), so gold and white stay apart once iOS tints them (as plain grey, gold and
    white are only 1.4:1 apart). Alpha kept."""
    from .compose import luminance, to_srgb
    from .layers import emblem_colours
    arr = np.asarray(layer.convert("RGBA"), dtype=np.float64)
    y = luminance(arr[..., :3])
    levels = [float(luminance(c)) for c in emblem_colours()]
    lo, hi = min(levels), max(levels)
    if hi - lo > 1e-6:
        y = 0.4 + np.clip((y - lo) / (hi - lo), 0, 1) * 0.6
    g = to_srgb(y)
    return Image.fromarray(np.round(np.dstack([g, g, g, arr[..., 3]])).astype(np.uint8), "RGBA")


def ios_tile(emblem, size):
    """The iOS icon as shipped: the emblem on the brand background (opaque, full bleed; iOS rounds the corners)."""
    return tile(trimmed(emblem), size, brand()["icon"]["ios"]["emblem"])


def android_tile(emblem, size):
    """What an Android launcher shows of the adaptive icon (its middle 72 dp), before the launcher's mask."""
    a = brand()["icon"]["android"]
    return tile(trimmed(emblem), size, a["emblemDp"] / a["visibleDp"], a["safeRadiusDp"] / a["visibleDp"])


def white_on_clear(mask):
    out = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def icon_shape(emblem, size, edge=0):
    """The app icon as people see it on a home screen (the iOS shape): for the feature graphic and the social image.
    With edge, a ring that many pixels wide in the decorative outline colour, so the navy tile still shows its shape
    on a navy background (the result is that much bigger on each side)."""
    icon = masked(ios_tile(emblem, size), superellipse((size, size), 5.0))
    if not edge:
        return icon
    out = Image.new("RGBA", (size + 2 * edge, size + 2 * edge), colour("outlineSubtle") + (255,))
    out = masked(out, superellipse(out.size, 5.0))
    out.alpha_composite(icon, (edge, edge))
    return out


# ----- The files -----

def png(image, mode=None):
    """PNG bytes without metadata, in a fixed mode."""
    buf = io.BytesIO()
    (image.convert(mode) if mode else image).save(buf, "PNG", compress_level=9)
    return buf.getvalue()


def ios_files(emblem):
    b = brand()["icon"]
    size, share = b["ios"]["size"], b["ios"]["emblem"]
    icon = ios_tile(emblem, size).convert("RGB")
    layer, _ = place(trimmed(emblem), (size, size), share * size)
    folder = f"{IOS_ASSETS}/AppIcon.appiconset"
    files = {f"{folder}/AppIcon.png": ("png", icon, "RGB"),
             f"{folder}/AppIcon-Dark.png": ("png", layer, "RGBA"),
             f"{folder}/AppIcon-Tinted.png": ("png", tinted(layer), "RGBA")}
    entries = [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
               {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png",
                "idiom": "universal", "platform": "ios", "size": "1024x1024"},
               {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png",
                "idiom": "universal", "platform": "ios", "size": "1024x1024"}]
    files[f"{folder}/Contents.json"] = ("text", json.dumps({"images": entries, "info": {"author": "xcode",
                                                                                         "version": 1}}, indent=2))
    pt = b["launch"]["pt"]
    launch = f"{IOS_ASSETS}/LaunchLogo.imageset"
    images = []
    for s in b["launch"]["scales"]:
        px = pt * s
        logo, _ = place(trimmed(emblem), (px, px), px)
        files[f"{launch}/LaunchLogo@{s}x.png"] = ("png", logo, "RGBA")
        images.append({"filename": f"LaunchLogo@{s}x.png", "idiom": "universal", "scale": f"{s}x"})
    images.insert(0, {"idiom": "universal", "scale": "1x"})
    files[f"{launch}/Contents.json"] = ("text", json.dumps({"images": images, "info": {"author": "xcode",
                                                                                        "version": 1}}, indent=2))
    return files


def android_files(emblem):
    a = brand()["icon"]["android"]
    canvas, visible = a["canvasDp"], a["visibleDp"]
    files = {}
    mono = silhouette(trimmed(emblem))
    em = trimmed(emblem)
    leg = brand()["icon"]["legacy"]
    sp = brand()["icon"]["splash"]
    for name, d in a["densities"].items():
        px = round(canvas * d)
        fg, _ = place(em, (px, px), a["emblemDp"] * d, a["safeRadiusDp"] * d)
        files[f"{RES}/mipmap-{name}/ic_launcher_foreground.png"] = ("png", fg, "RGBA")
        bg = background((px, px), reach=brand()["background"]["reach"] * visible / canvas)
        files[f"{RES}/mipmap-{name}/ic_launcher_background.png"] = ("png", bg, "RGB")
        m, _ = place(white_on_clear(mono), (px, px), a["emblemDp"] * d, a["safeRadiusDp"] * d)
        files[f"{RES}/mipmap-{name}/ic_launcher_monochrome.png"] = ("png", m, "RGBA")
        # API 24-25: a finished icon, a rounded square and a circle inset 2 dp in a 48 dp square.
        lpx = round(leg["sizeDp"] * d)
        inset = leg["insetDp"] / (leg["sizeDp"] / 2)
        full = tile(em, lpx, leg["emblem"] * (1 - inset))
        corner = leg["cornerDp"] / (leg["sizeDp"] / 2 - leg["insetDp"])
        files[f"{RES}/mipmap-{name}/ic_launcher.png"] = ("png", masked(full, rounded((lpx, lpx), corner, inset=inset)),
                                                         "RGBA")
        files[f"{RES}/mipmap-{name}/ic_launcher_round.png"] = ("png", masked(full, rounded((lpx, lpx), 1.0,
                                                                                           inset=inset)), "RGBA")
        spx = round(sp["canvasDp"] * d)
        splash, _ = place(em, (spx, spx), sp["emblemDp"] * d, sp["safeRadiusDp"] * d)
        files[f"{RES}/drawable-{name}/splash_emblem.png"] = ("png", splash, "RGBA")
    adaptive = ('<?xml version="1.0" encoding="utf-8"?>\n'
                "<!-- Written by tools/make_art.py export icons (docs/STORE_ART.md): the emblem on the brand's navy, "
                "and its silhouette for themed icons (Android 13+). -->\n"
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
                "</adaptive-icon>\n")
    files[f"{RES}/mipmap-anydpi-v26/ic_launcher.xml"] = ("text", adaptive)
    files[f"{RES}/mipmap-anydpi-v26/ic_launcher_round.xml"] = ("text", adaptive)
    colours_xml = (ROOT / RES / "values" / "colors.xml").read_text(encoding="utf-8")
    navy = "#FF" + "".join(f"{v:02X}" for v in colour("navy"))
    line = f'<color name="ic_launcher_background">{navy}</color>'
    if re.search(r'<color name="ic_launcher_background">[^<]*</color>', colours_xml):
        colours_xml = re.sub(r'<color name="ic_launcher_background">[^<]*</color>', line, colours_xml)
    else:
        colours_xml = colours_xml.replace("</resources>", f"    {line}\n</resources>")
    files[f"{RES}/values/colors.xml"] = ("text", colours_xml)
    return files


def store_files(emblem, art):
    # Play's icon is the launcher icon as Android shows it: the 72 dp in the middle of the 108 dp layers (32-bit, as
    # the Fastfile checks, though every pixel is opaque).
    icon = android_tile(emblem, brand()["icon"]["play"]["size"])
    return {f"{PLAY}/icon.png": ("png", icon, "RGBA"),
            f"{PLAY}/featureGraphic.png": ("png", feature_graphic(emblem, art), "RGB")}


def web_files(emblem, art):
    w = brand()["icon"]["web"]
    em = trimmed(emblem)
    files = {}
    frames = []
    for s in (48, 32, 16):
        t = tile(em, s * 4, w["favicon"]).resize((s, s), Image.LANCZOS)
        frames.append(masked(t, rounded((s, s), w["faviconCorner"] * 2)))
    buf = io.BytesIO()
    frames[0].save(buf, "ICO", sizes=[(48, 48), (32, 32), (16, 16)], append_images=frames[1:])
    files[f"{WEB}/favicon.ico"] = ("bytes", buf.getvalue())
    files[f"{WEB}/apple-touch-icon.png"] = ("png", tile(em, 180, w["touch"]), "RGB")
    files[f"{WEB}/icon-192.png"] = ("png", tile(em, 192, w["touch"]), "RGB")
    files[f"{WEB}/icon-512.png"] = ("png", tile(em, 512, w["touch"]), "RGB")
    files[f"{WEB}/icon-maskable-512.png"] = ("png", tile(em, 512, w["maskable"], 0.4), "RGB")
    logo, _ = place(em, (w["emblemPx"], w["emblemPx"]), w["emblemPx"])
    files[f"{WEB}/emblem.png"] = ("png", logo, "RGBA")
    files[f"{WEB}/og-v2.png"] = ("png", og_image(emblem, art), "RGB")
    b = brand()
    manifest = {"name": b["name"], "short_name": b["name"], "start_url": "/", "display": "browser",
                "background_color": b["palette"]["navy"].lower(), "theme_color": b["palette"]["navy"].lower(),
                "icons": [{"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
                          {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"},
                          {"src": "/icon-maskable-512.png", "sizes": "512x512", "type": "image/png",
                           "purpose": "maskable"}]}
    files[f"{WEB}/manifest.webmanifest"] = ("text", json.dumps(manifest, indent=2))
    return files


# ----- The feature graphic and the social image -----

def cover(art, size):
    """art scaled to cover size, cropped around its middle."""
    w, h = size
    s = max(w / art.size[0], h / art.size[1])
    big = art.resize((max(w, round(art.size[0] * s)), max(h, round(art.size[1] * s))), Image.LANCZOS)
    x, y = (big.size[0] - w) // 2, (big.size[1] - h) // 2
    return big.crop((x, y, x + w, y + h))


def feature_graphic(emblem, art=None, guides=False, report=None):
    """Play's feature graphic (1024x500 RGB): the art (or the brand background), and in the left column the icon, the
    name and the tagline, set in Atkinson Hyperlegible Next (never drawn by the image model). With guides, the text
    area and the middle Play keeps for its play button are outlined; a report dict gets the words' area and the
    opacity of the scrim put behind them (both for the review sheet)."""
    from .text import draw_lines, face, fit, guard
    f = brand()["feature"]
    size = tuple(f["size"])
    canvas = (cover(art, size) if art is not None else background(size)).convert("RGBA")
    x0, y0, x1, y1 = f["column"]
    width = x1 - x0
    title, tagline = f["title"], f["tagline"]
    ft, fg = face(title["weight"]), face(tagline["weight"])
    ts, tl = fit(ft, brand()["name"], width, title["size"], title["min"], title["lines"])
    gs, gl = fit(fg, brand()["tagline"], width, tagline["size"], tagline["min"], tagline["lines"])
    icon = f["iconSize"]
    gap1, gap2 = 26, 22
    t_h = ts * 1.15 * (len(tl) - 1) + ft.cap * ts / ft.upem
    g_h = gs * 1.25 * (len(gl) - 1) + fg.cap * gs / fg.upem + 0.22 * gs
    block = icon + gap1 + t_h + gap2 + g_h
    top = round(y0 + (y1 - y0 - block) / 2)
    tbox = (x0, top + icon + gap1, x1, round(top + icon + gap1 + t_h))
    gbox = (x0, round(tbox[3] + gap2), x1, round(tbox[3] + gap2 + g_h))
    text_area = (x0, tbox[1], x1, gbox[3])
    scrim = guard(canvas, text_area, [title["colour"], tagline["colour"]])
    if report is not None:
        report.update(words=text_area, scrim=scrim)
    canvas.alpha_composite(icon_shape(emblem, icon - 6, edge=3), (x0, top))
    draw_lines(canvas, ft, tl, ts, tbox, colour(title["colour"]), align="left", valign="top", leading=1.15)
    draw_lines(canvas, fg, gl, gs, gbox, colour(tagline["colour"]), align="left", valign="top", leading=1.25)
    kx0, _, kx1, _ = f["keepClear"]
    if x1 > kx0 and x0 < kx1:
        raise ValueError("brand.json: the feature graphic's text column runs into the middle Play keeps clear")
    if guides:
        d = ImageDraw.Draw(canvas)
        d.rectangle(f["textBox"], outline=(255, 0, 255, 255), width=2)
        d.rectangle(f["keepClear"], outline=(0, 255, 255, 255), width=2)
    return canvas.convert("RGB")


def og_image(emblem, art=None, report=None):
    """The website's social image (1200x630 RGB): icon, name and tagline centred on the art or the brand background.
    A report dict gets what feature_graphic's does."""
    from .text import draw_lines, face, fit, guard
    o = brand()["og"]
    w, h = o["size"]
    canvas = (cover(art, (w, h)) if art is not None else background((w, h))).convert("RGBA")
    m = o["margin"]
    title, tagline = o["title"], o["tagline"]
    ft, fg = face(title["weight"]), face(tagline["weight"])
    ts, tl = fit(ft, brand()["name"], w - 2 * m, title["size"], title["min"], title["lines"])
    gs, gl = fit(fg, brand()["tagline"], w - 2 * m, tagline["size"], tagline["min"], tagline["lines"])
    icon = o["iconSize"]
    t_h = ts * 1.15 * (len(tl) - 1) + ft.cap * ts / ft.upem
    g_h = gs * 1.25 * (len(gl) - 1) + fg.cap * gs / fg.upem + 0.22 * gs
    block = icon + 40 + t_h + 26 + g_h
    top = round((h - block) / 2)
    tbox = (m, top + icon + 40, w - m, round(top + icon + 40 + t_h))
    gbox = (m, round(tbox[3] + 26), w - m, round(tbox[3] + 26 + g_h))
    text_area = (m, tbox[1], w - m, gbox[3])
    scrim = guard(canvas, text_area, [title["colour"], tagline["colour"]])
    if report is not None:
        report.update(words=text_area, scrim=scrim)
    canvas.alpha_composite(icon_shape(emblem, icon - 8, edge=4), ((w - icon) // 2, top))
    draw_lines(canvas, ft, tl, ts, tbox, colour(title["colour"]), valign="top", leading=1.15)
    draw_lines(canvas, fg, gl, gs, gbox, colour(tagline["colour"]), valign="top", leading=1.25)
    return canvas.convert("RGB")


# ----- export, check, pick -----

def out_root(out):
    """Where the files go: the repo, or a trial folder (relative to the repo unless absolute)."""
    if not out:
        return ROOT
    path = Path(out)
    return path if path.is_absolute() else ROOT / path


def render(what, emblem, art):
    files = {}
    if what in ("icons", "all"):
        files.update(ios_files(emblem))
        files.update(android_files(emblem))
    if what in ("store", "all"):
        files.update(store_files(emblem, art))
    if what in ("web", "all"):
        files.update(web_files(emblem, art))
    return files


def payload(spec):
    kind = spec[0]
    if kind == "png":
        return png(spec[1], spec[2])
    if kind == "text":
        text = spec[1]
        return (text if text.endswith("\n") else text + "\n").encode("utf-8")
    return spec[1]


def same(path, spec):
    """Whether the file on disk is what a fresh export makes: the same pixels and mode for images, the same text."""
    if not path.exists():
        return False
    if spec[0] == "png":
        with Image.open(path) as im:
            want = spec[1].convert(spec[2])
            return im.mode == want.mode and im.size == want.size and im.tobytes() == want.tobytes()
    if spec[0] == "text":
        return path.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n") == spec[1].rstrip("\n")
    if path.suffix == ".ico":
        return _ico_frames(path.read_bytes()) == _ico_frames(spec[1])
    return path.read_bytes() == spec[1]


def _ico_frames(data):
    with Image.open(io.BytesIO(data)) as im:
        return sorted((s, im.ico.getimage(s).convert("RGBA").tobytes()) for s in im.ico.sizes())


def run_export(what, out=None, icon=None, feature=None, check=False):
    if (icon or feature) and not out and not check:
        raise SystemExit("--icon/--feature are for a trial: add --out (the apps get only what the owner picked).")
    root = out_root(out)
    emblem = emblem_master(icon)
    art = feature_art(feature)
    files = render(what, emblem, art)
    if check:
        bad = [p for p, spec in sorted(files.items()) if not same(root / p, spec)]
        for p in bad:
            print(f"differs: {rel(root / p)}")
        print(f"{len(files) - len(bad)} of {len(files)} files match a fresh export" + ("" if bad else "."))
        return 1 if bad else 0
    for p, spec in sorted(files.items()):
        write_bytes(root / p, payload(spec))
    if out:
        # What this trial was made from, so make_art.py check --out can make it again and compare.
        write_json(root / "export.json", {"what": what, "icon": icon, "feature": feature, "made": now()})
    print(f"{len(files)} files -> {rel(root)}" + (" (a trial: the apps are untouched)" if out else ""))
    if not out and what in ("icons", "all"):
        for old in OLD:
            if (ROOT / old).exists():
                (ROOT / old).unlink()
                print(f"removed {old} (the old vector icon's layer-list)")
        _follow_ups()
    return 0


def _follow_ups():
    """What a real icon export can't safely change by itself (files other work owns): said out loud."""
    manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    if 'android:roundIcon="@mipmap/ic_launcher_round"' not in manifest:
        print('to do: AndroidManifest.xml android:roundIcon="@mipmap/ic_launcher_round"')
    for path in (ROOT / RES).rglob("*.xml"):
        if "@drawable/ic_launcher_foreground" in path.read_text(encoding="utf-8"):
            print(f"to do: {rel(path)} still uses @drawable/ic_launcher_foreground (the old vector): "
                  f"@mipmap/ic_launcher_foreground or @drawable/splash_emblem now")


def run_pick(kind, cid, budget_limit=None):
    """The owner's choice: recorded in brand/picks.json with its art copied to brand/masters/ (so exports never need
    the cache), and the icon's alt text filled in from its motif."""
    c = concept(cid)
    if c["kind"] != kind:
        raise SystemExit(f"{cid} is a {c['kind']} concept, not {kind}")
    data = picks()
    MASTERS.mkdir(parents=True, exist_ok=True)
    source = Entry(c["key"])
    motif = next((m for m in prompts(kind)["motifs"] if m["id"] == c.get("motif")), {})
    alts = alt_text()
    if kind == "icon":
        from .layers import emblem_of, run_layers
        layer = emblem_of(cid) or run_layers(cid, "auto", None, budget_limit)
        if layer is None:
            raise SystemExit(f"{cid} has no usable layer: it needs a vector redraw before it can be exported")
        shutil.copyfile(source.path(c.get("image", 0)), MASTERS / "icon-concept.webp")
        write_bytes(MASTERS / "icon-emblem.png", png(layer, "RGBA"))
        data["icon"] = {"id": cid, "concept": c["key"], "layer": concept(cid)["layer"]["key"],
                        "motif": c.get("motifName"), "picked": date.today().isoformat()}
        if motif.get("alt"):
            alts["icon"] = f"Epic Audio Games app icon: {motif['alt']}, on navy."
            alts["emblem"] = f"Epic Audio Games logo: {motif['alt']}."
    else:
        shutil.copyfile(source.path(c.get("image", 0)), MASTERS / "feature-art.webp")
        data["feature"] = {"id": cid, "concept": c["key"], "motif": c.get("motifName"),
                           "picked": date.today().isoformat()}
        if motif.get("alt"):
            alts["featureGraphic"] = f"Epic Audio Games: audio story games you play by voice. {motif['alt'].capitalize()}."
    save_picks(data)
    save_alt_text(alts)
    print(f"picked {cid} for the {kind}: brand/picks.json, brand/masters/ (export next: make_art.py export all)")
