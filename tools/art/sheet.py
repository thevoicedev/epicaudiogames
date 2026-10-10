"""The review sheets for the approval gates: build/art/review/<kind>.html (with its images in build/art/review/<kind>/)
and one <kind>.png of the whole sheet. build/art/ is scratch: never committed.

Icons are judged the way blind and partially sighted players meet them: at the sizes phones really draw them (down
to 29 and 16 pixels, plus a close-up of those two), in every home-screen shape, on light, dark and busy wallpapers,
as the iOS dark and tinted variants and the Android themed icon, in grey and as people with protanopia,
deuteranopia and tritanopia see them, with each emblem colour's contrast against the background around it (flagged
under 3:1), the contrast where one emblem colour sits on another (gold bars on a white bubble: flagged under 3:1 too)
and how much of the emblem stays at least a pixel thick at 29 and 16 pixels.

The feature graphic and the social image are shown on each feature concept with Play's guides, the words' contrast
against the art behind them, any scrim the words needed (it shows as a box), and how much art sits in the middle where
Play puts its play button.
"""
import html

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from .brand import BUILD, brand, colour, font_path, prompts, rel, shots_spec, write_text
from .cache import Entry, concepts
from .compose import anatomy, masked, place, shapes, simulate, superellipse, trimmed, wallpaper

SIZES = [180, 120, 87, 60, 40, 29, 16]
INK = (17, 20, 32)
PAPER = (232, 234, 240)
FLAG = (164, 22, 26)


def _font(size, weight="regular"):
    path = font_path(weight)
    return ImageFont.truetype(str(path), size) if path else ImageFont.load_default()


def ios(image, size):
    """The icon at size px with the iOS shape."""
    return masked(image.convert("RGB").resize((size, size), Image.LANCZOS), superellipse((size, size), 5.0))


def thickness(emblem_alpha, at):
    """How much of the emblem is at least one pixel thick when the icon is `at` pixels wide (erosion test, worked at
    a quarter of the master's size)."""
    m = Image.fromarray(((np.asarray(emblem_alpha) > 127) * 255).astype(np.uint8), "L")
    m = m.resize((256, 256), Image.BOX)
    m = m.point(lambda v: 255 if v > 127 else 0)
    r = max(1, round(256 / at / 2))
    eroded = m.filter(ImageFilter.MinFilter(2 * r + 1))
    total = np.count_nonzero(np.asarray(m))
    return round(np.count_nonzero(np.asarray(eroded)) / max(1, total), 2)


def touching(placed, ring=6):
    """Where one emblem colour sits on another (gold bars inside a white bubble): for each such pair, how much of the
    ring around the inner colour's parts is the outer colour, and the two colours' contrast. A pair under 3:1 reads as
    one shape to many low-vision players, and the inner parts vanish in grey and in the tinted icon, however well both
    stand out from the navy. placed: the emblem on a transparent 1024 canvas; ring in its pixels."""
    from .compose import _dilate, hex_of, ratio
    from .layers import emblem_colours
    arr = np.asarray(placed.convert("RGBA"), dtype=np.float64)
    solid = arr[..., 3] >= 128
    palette = emblem_colours()
    nearest = np.argmin(np.stack([np.linalg.norm(arr[..., :3] - c, axis=2) for c in palette]), axis=0)
    pairs = {}
    for i, inner in enumerate(palette):
        mine = solid & (nearest == i)
        if mine.sum() < 0.02 * max(1, solid.sum()):
            continue
        around = _dilate(mine, ring) & ~mine
        for j, outer in enumerate(palette):
            if j == i or not around.any():
                continue
            share = float((around & solid & (nearest == j)).sum() / around.sum())
            pair = tuple(sorted((i, j)))
            if share >= 0.15 and share > pairs.get(pair, {}).get("share", 0):
                pairs[pair] = {"inner": hex_of(inner), "outer": hex_of(outer), "share": round(share, 2),
                               "contrast": round(ratio(inner, outer), 2)}
    return list(pairs.values())


def variants(layer, size):
    """iOS dark (the emblem on the system's dark backdrop), iOS tinted (the tinted export's greys, tinted, on black)
    and the Android themed icon (the monochrome layer in the theme's dark tone on its light tone)."""
    from .icons import android_tile, silhouette, tinted
    share = brand()["icon"]["ios"]["emblem"]
    em = trimmed(layer)
    y = np.linspace(0, 1, size)[:, None].repeat(size, 1)
    dark_bg = Image.fromarray(np.dstack([np.round(50 - 30 * y)] * 3).astype(np.uint8), "RGB").convert("RGBA")
    fg, _ = place(em, (size, size), share * size)
    dark = masked(Image.alpha_composite(dark_bg, fg), superellipse((size, size)))
    g = np.asarray(tinted(fg), dtype=np.float64)
    tint = np.array([255, 196, 120.0]) / 255.0
    tinted_fg = Image.fromarray(np.dstack([g[..., :3] * tint, g[..., 3]]).astype(np.uint8), "RGBA")
    black = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    tinted_icon = masked(Image.alpha_composite(black, tinted_fg), superellipse((size, size)))
    a = brand()["icon"]["android"]
    sil = silhouette(em)
    white = Image.merge("RGBA", [Image.new("L", sil.size, 255)] * 3 + [sil])
    mono, _ = place(white, (size, size), a["emblemDp"] / a["visibleDp"] * size, a["safeRadiusDp"] / a["visibleDp"]
                    * size)
    tone = Image.new("RGBA", (size, size), (216, 226, 255, 255))
    ink = Image.new("RGBA", (size, size), (34, 62, 112, 255))
    ink.putalpha(mono.getchannel("A"))
    themed = masked(Image.alpha_composite(tone, ink), shapes((size, size))["circle"])
    return {"iOS dark": dark, "iOS tinted": tinted_icon, "Android themed": themed}


def _row_images(cid, c, assets):
    """Every picture for one concept, saved for the HTML; returns them and the numbers. Everything but the "as
    generated" thumbnail shows the icon as it would ship: the emblem cut out and placed on the brand background at
    brand.json's size (the iOS composition, and Android's adaptive one under the Android masks)."""
    from .icons import android_tile, ios_tile
    from .layers import cut_local, emblem_of, finish
    image = Entry(c["key"]).image(c.get("image", 0)).convert("RGB")
    layer = emblem_of(cid)
    if layer is None:
        layer = finish(cut_local(image)[0])[0]
    shipped = ios_tile(layer, 1024).convert("RGB")
    droid = android_tile(layer, 1024).convert("RGB")
    facts = anatomy(shipped)
    placed, _ = place(trimmed(layer), (1024, 1024), brand()["icon"]["ios"]["emblem"] * 1024)
    facts["thick29"] = thickness(placed.getchannel("A"), 29)
    facts["thick16"] = thickness(placed.getchannel("A"), 16)
    facts["touching"] = touching(placed)
    out = {"concept": ios(image, 100), "big": ios(shipped, 240), "sizes": [(s, ios(shipped, s)) for s in SIZES]}
    masks = shapes((88, 88))
    out["shapes"] = [("iOS", masked(shipped.resize((88, 88), Image.LANCZOS), masks.pop("iOS")))]
    out["shapes"] += [(name, masked(droid.resize((88, 88), Image.LANCZOS), m)) for name, m in masks.items()]
    small = shipped.resize((88, 88), Image.LANCZOS)
    out["vision"] = [(kind, masked(simulate(small, kind), superellipse((88, 88))))
                     for kind in ("grayscale", "protanopia", "deuteranopia", "tritanopia")]
    out["variants"] = list(variants(layer, 88).items())
    walls = []
    for kind in ("light", "dark", "busy"):
        wp = wallpaper(kind, (120, 120)).convert("RGBA")
        wp.alpha_composite(ios(shipped, 60), (8, 8))
        wp.alpha_composite(ios(shipped, 29), (80, 80))
        walls.append((kind, wp))
    out["walls"] = walls
    shipped.resize((512, 512), Image.LANCZOS).save(assets / f"{cid}.png")
    image.resize((256, 256), Image.LANCZOS).save(assets / f"{cid}-concept.png")
    strip = Image.new("RGB", (sum(SIZES) + 16 * len(SIZES), 180), PAPER)
    x = 0
    for s, im in out["sizes"]:
        strip.paste(im, (x, 180 - s), im)
        x += s + 16
    strip.save(assets / f"{cid}-sizes.png")
    for name in ("shapes", "vision", "variants", "walls"):
        items = out[name]
        w = sum(im.size[0] for _, im in items) + 12 * (len(items) - 1)
        h = max(im.size[1] for _, im in items)
        s = Image.new("RGB", (w, h), PAPER)
        x = 0
        for _, im in items:
            s.paste(im, (x, 0), im)
            x += im.size[0] + 12
        s.save(assets / f"{cid}-{name}.png")
    return out, facts, layer


def _flags(facts):
    flags = []
    if facts.get("minContrast") is not None and facts["minContrast"] < 3:
        flags.append(f"a colour under 3:1 against its background ({facts['minContrast']}:1)")
    if facts["extent"] < 0.45:
        flags.append(f"small emblem ({facts['extent']:.0%} of the square)")
    if facts["extent"] > 0.85:
        flags.append(f"emblem nearly touches the edges ({facts['extent']:.0%})")
    if facts["thick29"] < 0.35:
        flags.append(f"thin at 29 px (only {facts['thick29']:.0%} stays a pixel thick)")
    for t in facts.get("touching", []):
        if t["contrast"] < 3:
            flags.append(f"{t['inner']} sits on {t['outer']} inside the emblem at {t['contrast']}:1 (lost in grey, "
                         f"in the tinted icon and to many low-vision players)")
    return flags


def icon_sheet(ids=None):
    out_dir = BUILD / "review"
    assets = out_dir / "icon"
    assets.mkdir(parents=True, exist_ok=True)
    found = concepts("icon")
    chosen = {cid: c for cid, c in found.items() if not ids or cid in ids}
    if not chosen:
        raise SystemExit("no icon concepts yet: make_art.py concepts icon")
    motifs = {m["id"]: m for m in prompts("icon")["motifs"]}
    rows = []
    for cid, c in chosen.items():
        print(f"  {cid}...")
        imgs, facts, layer = _row_images(cid, c, assets)
        meta = Entry(c["key"]).meta or {}
        rows.append((cid, c, imgs, facts, meta, motifs.get(c.get("motif"), {})))
    png = _icon_png(rows)
    png.save(out_dir / "icon.png", optimize=True)
    _small_png(rows).save(out_dir / "icon-small.png")
    write_text(out_dir / "icon.html", _icon_html(rows))
    print(f"review sheet: {rel(out_dir / 'icon.html')}, {rel(out_dir / 'icon.png')}, {rel(out_dir / 'icon-small.png')}")


def _icon_png(rows):
    row_h, width = 410, 1830
    sheet = Image.new("RGB", (width, 70 + row_h * len(rows)), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((24, 18), "Epic Audio Games: icon concepts (gate 3)", font=_font(28, "bold"), fill=INK)
    small, label, bold = _font(15), _font(17), _font(20, "bold")
    for n, (cid, c, imgs, facts, meta, motif) in enumerate(rows):
        top = 70 + n * row_h
        d.line((0, top, width, top), fill=(190, 194, 206), width=2)
        d.text((24, top + 10), f"{cid}  ·  motif {c.get('motif')} {c.get('motifName', '')}  ·  {c.get('model')} "
                               f"{c.get('quality')}  ·  ${meta.get('cost_usd', 0):.4f}"
                               + (f"  ·  refined from {c['parent']}" if c.get("parent") else ""), font=bold, fill=INK)
        cols = ", ".join(f"{x['colour']} {x['contrast']}:1" for x in facts["colours"])
        inside = "".join(f"; {t['inner']} on {t['outer']} inside it: {t['contrast']}:1" for t in facts["touching"])
        d.text((24, top + 38), f"emblem {facts['extent']:.0%} of the square; colours (contrast with the background "
                               f"around them): {cols}{inside}; a pixel thick at 29 px: {facts['thick29']:.0%}, at "
                               f"16 px: {facts['thick16']:.0%}", font=label, fill=INK)
        flags = _flags(facts)
        if flags:
            d.text((24, top + 60), "check: " + "; ".join(flags), font=label, fill=FLAG)
        y0 = top + 88
        sheet.paste(imgs["big"], (24, y0), imgs["big"])
        d.text((144, y0 + 248), "as shipped (iOS)", font=small, fill=INK, anchor="mt")
        x = 290
        for s, im in imgs["sizes"]:
            sheet.paste(im, (x, y0 + 180 - s), im)
            d.text((x + s // 2, y0 + 188), str(s), font=small, fill=INK, anchor="mt")
            x += s + 18
        sheet.paste(imgs["concept"], (290, y0 + 216), imgs["concept"])
        d.text((400, y0 + 266), "the concept as generated", font=small, fill=INK, anchor="lm")
        for name, gy in (("shapes", 0), ("vision", 130)):
            x = 960
            for title, im in imgs[name]:
                sheet.paste(im, (x, y0 + gy), im)
                d.text((x + 44, y0 + gy + 94), title, font=small, fill=INK, anchor="mt")
                x += 88 + 16
        x = 1490
        for title, im in imgs["variants"]:
            sheet.paste(im, (x, y0), im)
            d.text((x + 44, y0 + 94), title, font=small, fill=INK, anchor="mt")
            x += 88 + 24
        x = 1450
        for title, im in imgs["walls"]:
            sheet.paste(im, (x, y0 + 130), im)
            d.text((x + 60, y0 + 254), title, font=small, fill=INK, anchor="mt")
            x += 120 + 4
    return sheet


def _small_png(rows):
    """Every concept at 29 and 16 px, actual size and magnified 4x (nearest neighbour), on light and dark."""
    cell = 214
    sheet = Image.new("RGB", (24 + cell * len(rows), 490), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((24, 12), "29 px and 16 px: actual size (top left), then magnified 4x", font=_font(22, "bold"), fill=INK)
    for i, (cid, c, imgs, facts, meta, motif) in enumerate(rows):
        x = 24 + i * cell
        d.text((x, 50), cid, font=_font(17, "bold"), fill=INK)
        sizes = dict(imgs["sizes"])
        for kind, y in (("light", 82), ("dark", 290)):
            wp = wallpaper(kind, (cell - 14, 180)).convert("RGBA")
            wp.alpha_composite(sizes[29], (8, 8))
            wp.alpha_composite(sizes[16], (46, 14))
            wp.alpha_composite(sizes[29].resize((116, 116), Image.NEAREST), (8, 50))
            wp.alpha_composite(sizes[16].resize((64, 64), Image.NEAREST), (132, 50))
            sheet.paste(wp, (x, y), wp)
    return sheet


def _icon_html(rows):
    css = ("body{font-family:system-ui,sans-serif;background:#F3F5FB;color:#0B1430;margin:0 auto;max-width:1200px;"
           "padding:16px;line-height:1.45}h1,h2{color:#16275E}section{border-top:2px solid #6B7699;padding:8px 0 24px}"
           "img{max-width:100%;height:auto;image-rendering:auto}code{background:#FFFFFF;border:2px solid #6B7699;"
           "padding:2px 6px;border-radius:6px}.flag{color:#A4161A;font-weight:700}.strip{display:block;margin:8px 0}"
           "figure{margin:0}figcaption{font-size:.95em}")
    parts = [f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' "
             f"content='width=device-width,initial-scale=1'><title>Icon concepts</title><style>{css}</style></head>"
             f"<body><h1>Icon concepts for Epic Audio Games (approval gate 3)</h1>"
             f"<p>Each concept at the sizes phones draw it, in every home-screen shape, as the iOS dark and tinted "
             f"variants and the Android themed icon, in grey and as people with colour-vision deficiencies see it, "
             f"and on light, dark and busy wallpapers. Contrast is each emblem colour against the background right "
             f"around it (3:1 is the minimum for graphics). To choose one, run the command under it.</p>"
             f"<p><img src='icon-small.png' alt='Every concept at 29 and 16 pixels, actual size and magnified, on "
             f"light and dark wallpapers.'></p>"]
    for cid, c, imgs, facts, meta, motif in rows:
        alt = motif.get("alt", "an emblem")
        cols = ", ".join(f"{x['colour']} at {x['contrast']}:1 ({x['share']:.0%} of it)" for x in facts["colours"])
        flags = _flags(facts)
        parts.append(
            f"<section aria-labelledby='{cid}'><h2 id='{cid}'>{cid}: {html.escape(c.get('motifName', ''))}</h2>"
            f"<p>Motif {c.get('motif')}: {html.escape(motif.get('about', ''))}. {html.escape(c.get('model', ''))}, "
            f"{c.get('quality')} quality, ${meta.get('cost_usd', 0):.4f}"
            + (f", refined from {c['parent']}" if c.get('parent') else "") + ".</p>"
            f"<figure><img src='icon/{cid}.png' width='256' height='256' alt='{html.escape(alt)}, on navy, as it "
            f"would ship.'> <img src='icon/{cid}-concept.png' width='128' height='128' alt='The concept as the model "
            f"drew it.'><figcaption>As it would ship (the emblem cut out and placed on the brand background), and "
            f"the concept as generated. Alt text if picked: Epic Audio Games app icon: {html.escape(alt)}, on navy."
            f"</figcaption></figure>"
            f"<ul><li>Emblem: {facts['extent']:.0%} of the square, covering {facts['fill']:.0%} of it.</li>"
            f"<li>Colours: {cols}.</li>"
            + "".join(f"<li>{t['inner']} sits on {t['outer']} inside the emblem ({t['share']:.0%} of the edge "
                      f"around it): {t['contrast']}:1.</li>" for t in facts["touching"])
            + f"<li>A pixel thick at 29 px: {facts['thick29']:.0%}; at 16 px: {facts['thick16']:.0%}.</li></ul>"
            + (f"<p class='flag'>Check: {html.escape('; '.join(flags))}.</p>" if flags else "")
            + f"<img class='strip' src='icon/{cid}-sizes.png' alt='{cid} at 180, 120, 87, 60, 40, 29 and 16 pixels.'>"
            f"<img class='strip' src='icon/{cid}-shapes.png' alt='{cid} in the iOS shape and the Android circle, "
            f"squircle, teardrop and rounded-square masks.'>"
            f"<img class='strip' src='icon/{cid}-variants.png' alt='{cid} as the iOS dark icon, the iOS tinted icon "
            f"and the Android themed icon.'>"
            f"<img class='strip' src='icon/{cid}-vision.png' alt='{cid} in grey and with protanopia, deuteranopia and "
            f"tritanopia.'>"
            f"<img class='strip' src='icon/{cid}-walls.png' alt='{cid} on a light, a dark and a busy wallpaper.'>"
            f"<p>Pick it: <code>py -3.13 tools/make_art.py pick icon {cid}</code></p></section>")
    parts.append("</body></html>")
    return "\n".join(parts)


# ----- feature graphic -----

def feature_facts(art, fg_report, og_report):
    """What gate 4 judges, in numbers: each picture's words against the art behind them (the worst 5% of its pixels,
    before any scrim: guard() puts a navy scrim behind words under 7:1, which shows as a box), the scrim each picture
    got, and how much of Play's middle 220 px (where its play button goes when the listing has a video) stands out
    from the navy at 3:1 or more. The reports are feature_graphic's and og_image's."""
    from .compose import background, contrast, luminance
    from .icons import cover
    from .text import worst_contrast
    f, o = brand()["feature"], brand()["og"]

    def plain(size):
        return (cover(art, size) if art is not None else background(size)).convert("RGB")

    fg_plain, og_plain = plain(tuple(f["size"])), plain(tuple(o["size"]))
    middle = luminance(np.asarray(fg_plain.crop(tuple(f["keepClear"])), dtype=np.float64))
    navy = luminance(np.array(colour("navy"), dtype=np.float64))
    return {"feature": worst_contrast(fg_plain, fg_report["words"], [f["title"]["colour"], f["tagline"]["colour"]]),
            "featureScrim": fg_report["scrim"],
            "og": worst_contrast(og_plain, og_report["words"], [o["title"]["colour"], o["tagline"]["colour"]]),
            "ogScrim": og_report["scrim"],
            "middle": float((contrast(middle, navy) >= 3).mean())}


def _feature_lines(facts):
    def words(ratios, scrim):
        said = ", ".join(f"{c} {r:.1f}:1" for c, r in ratios.items())
        return said + (f" on the art, so a {scrim:.0%} navy scrim goes behind them (to 7:1 or more)" if scrim
                       else " on the art (7:1 at least), no scrim")
    return [f"Play: the words {words(facts['feature'], facts['featureScrim'])}.",
            f"Social image: the words {words(facts['og'], facts['ogScrim'])}.",
            f"Play's middle 220 px, where its play button goes: {facts['middle']:.1%} of it stands out from the "
            f"navy (3:1 or more)."]


def _feature_flags(facts):
    flags = []
    for where, key in (("the feature graphic", "featureScrim"), ("the social image", "ogScrim")):
        if facts[key]:
            flags.append(f"a scrim box shows behind the words on {where}")
    if facts["middle"] > 0.01:
        flags.append("art in the middle, where Play's play button would cover it")
    return flags


def feature_sheet(ids=None):
    import textwrap
    from .icons import feature_graphic, og_image
    from .layers import cut_local, emblem_of, finish
    out_dir = BUILD / "review"
    assets = out_dir / "feature"
    assets.mkdir(parents=True, exist_ok=True)
    from .brand import picks
    p = picks()
    icon_id = (p.get("icon") or {}).get("id") or next(iter(concepts("icon")), None)
    if icon_id is None:
        raise SystemExit("no icon concept to put on the feature graphic yet")
    picked = (p.get("feature") or {}).get("id")
    emblem = emblem_of(icon_id)
    if emblem is None:
        c = concepts("icon")[icon_id]
        emblem = finish(cut_local(Entry(c["key"]).image(c.get("image", 0)))[0])[0]
    arts = [("brand background", None)]
    for cid, c in concepts("feature").items():
        if not ids or cid in ids:
            arts.append((cid, Entry(c["key"]).image(c.get("image", 0)).convert("RGB")))
    tiles = []
    for name, art in arts:
        fg_report, og_report = {}, {}
        fg = feature_graphic(emblem, art, guides=True, report=fg_report)
        og = og_image(emblem, art, report=og_report)
        slug = name.replace(" ", "-")
        fg.save(assets / f"{slug}-feature.png")
        og.save(assets / f"{slug}-og.png")
        tiles.append((name, fg, og, feature_facts(art, fg_report, og_report)))
    sheet = Image.new("RGB", (24 + 1024 + 24 + 600 + 24, 60 + len(tiles) * 560), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((24, 16), f"Feature graphic and social image (gate 4), with {icon_id}; magenta: Play's text area, cyan: "
                     f"the middle Play keeps clear", font=_font(22, "bold"), fill=INK)
    small = _font(15)
    for i, (name, fg, og, facts) in enumerate(tiles):
        y = 60 + i * 560
        d.text((24, y), name + ("  (picked now)" if name == picked else ""), font=_font(20, "bold"), fill=INK)
        sheet.paste(fg, (24, y + 32))
        sheet.paste(og.resize((600, 315), Image.LANCZOS), (24 + 1024 + 24, y + 32))
        ty = y + 32 + 315 + 10
        for text, fill in [(t, INK) for t in _feature_lines(facts)] + [(f"check: {t}", FLAG)
                                                                       for t in _feature_flags(facts)]:
            for part in textwrap.wrap(text, 84):
                d.text((24 + 1024 + 24, ty), part, font=small, fill=fill)
                ty += 19
    sheet.save(out_dir / "feature.png", optimize=True)
    css = ("body{font-family:system-ui,sans-serif;background:#F3F5FB;color:#0B1430;max-width:1100px;margin:auto;"
           "padding:16px;line-height:1.45}h1,h2{color:#16275E}section{border-top:2px solid #6B7699;padding:8px 0 24px}"
           "img{max-width:100%;display:block;margin:8px 0}code{background:#FFFFFF;border:2px solid #6B7699;"
           "padding:2px 6px;border-radius:6px}.flag{color:#A4161A;font-weight:700}")
    body = []
    for n, _, _, facts in tiles:
        slug = n.replace(" ", "-")
        flags = _feature_flags(facts)
        swap = ("<p>Pick it: <code>py -3.13 tools/make_art.py pick feature {0}</code>, then <code>py -3.13 "
                "tools/make_art.py export store</code> and <code>py -3.13 tools/make_art.py export web</code> (the "
                "social image, og-v2.png, is made from the same art).</p>".format(n)) if n.startswith("feature-") \
            else ""
        body.append(f"<section aria-labelledby='{slug}'><h2 id='{slug}'>{html.escape(n)}"
                    + (" (picked now)" if n == picked else "") + "</h2>"
                    f"<img src='feature/{slug}-feature.png' alt='The feature graphic on {html.escape(n)}, with "
                    f"guides.'><img src='feature/{slug}-og.png' alt='The social image on {html.escape(n)}.'>"
                    "<ul>" + "".join(f"<li>{html.escape(t)}</li>" for t in _feature_lines(facts)) + "</ul>"
                    + (f"<p class='flag'>Check: {html.escape('; '.join(flags))}.</p>" if flags else "")
                    + swap + "</section>")
    write_text(out_dir / "feature.html",
               f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' "
               f"content='width=device-width,initial-scale=1'><title>Feature art</title><style>{css}</style></head>"
               f"<body><h1>Feature graphic and social image (approval gate 4)</h1><p>Play's feature graphic and the "
               f"website's social image on the plain brand background and on each concept, with {icon_id}. Magenta "
               f"outlines Play's text area, cyan the middle Play keeps clear for its play button. Contrast is each "
               f"colour of words against the worst 5% of the art behind them, before any scrim; below 7:1 the tool "
               f"puts a navy scrim behind them, which shows as a box.</p>" + "".join(body) + "</body></html>")
    print(f"review sheet: {rel(out_dir / 'feature.html')}, {rel(out_dir / 'feature.png')}")


# ----- screenshots -----

def shots_sheet(out=None):
    spec = shots_spec()
    from .icons import out_root
    root = out_root(out)
    found = []
    for platform in ("android", "ios"):
        folder = root / spec[platform]["out"]
        found += [(platform, p) for p in sorted(folder.glob("*.png"))] if folder.exists() else []
    if not found:
        raise SystemExit("no framed screenshots yet: make_art.py shots android|ios")
    out_dir = BUILD / "review"
    cols = 4
    th = 480
    tw = 270
    sheet = Image.new("RGB", (24 + cols * (tw + 24), 60 + -(-len(found) // cols) * (th + 50)), PAPER)
    d = ImageDraw.Draw(sheet)
    d.text((24, 16), "Store screenshots (gate 4)", font=_font(22, "bold"), fill=INK)
    for i, (platform, p) in enumerate(found):
        with Image.open(p) as im:
            t = im.convert("RGB").resize((tw, round(tw * im.size[1] / im.size[0])), Image.LANCZOS)
        x, y = 24 + (i % cols) * (tw + 24), 60 + (i // cols) * (th + 50)
        sheet.paste(t.crop((0, 0, tw, min(th, t.size[1]))), (x, y))
        d.text((x, y + th + 6), f"{platform}: {p.name}", font=_font(15), fill=INK)
    sheet.save(out_dir / "shots.png", optimize=True)
    body = "".join(f"<figure><img src='{html.escape((root / spec[pl]['out'] / p.name).as_uri())}' width='270' "
                   f"alt='{html.escape(p.stem)}'><figcaption>{pl}: {html.escape(p.name)}</figcaption></figure>"
                   for pl, p in found)
    write_text(out_dir / "shots.html", "<!doctype html><html lang='en'><head><meta charset='utf-8'><title>Store "
                                       "screenshots</title><style>body{font-family:system-ui;background:#F3F5FB;"
                                       "color:#0B1430;padding:16px}figure{display:inline-block;margin:8px}</style>"
                                       "</head><body><h1>Store screenshots (approval gate 4)</h1>" + body +
               "</body></html>")
    print(f"review sheet: {rel(out_dir / 'shots.html')}, {rel(out_dir / 'shots.png')}")


def run_sheet(kind, ids=None, out=None):
    print(f"{kind} review sheet:")
    if kind == "icon":
        icon_sheet(ids)
    elif kind == "feature":
        feature_sheet(ids)
    else:
        shots_sheet(out)
