"""Words on the store art in Atkinson Hyperlegible Next (the apps' font, android/app/src/main/res/font/), kerned by
hand: this Pillow has no raqm, and the font keeps its kerning in GPOS, which Pillow's basic layout never reads. So
each glyph is placed here, at its advance plus the GPOS pair adjustment (fontTools), and drawn on its own.

Captions use *stars* around the words drawn in the key colour (gold), the rest in the main colour (white). guard()
puts a navy scrim behind text until the text has at least 7:1 against the worst 5% of the pixels behind it.
"""
import re

import numpy as np
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

from .brand import colour, font_path
from .compose import contrast, luminance

_faces = {}


class Face:
    """One weight of the font: glyph advances and GPOS kerning (fontTools), drawing (Pillow, FreeType)."""

    def __init__(self, weight):
        path = font_path(weight)
        if path is None:
            raise FileNotFoundError(f"the {weight} Atkinson Hyperlegible Next font isn't in android/app/src/main/res/"
                                    f"font/ yet")
        self.path = path
        tt = TTFont(str(path), lazy=False)
        self.upem = tt["head"].unitsPerEm
        self.cmap = tt.getBestCmap()
        self.advance = {g: m[0] for g, m in tt["hmtx"].metrics.items()}
        self.ascent = tt["OS/2"].sTypoAscender
        self.cap = getattr(tt["OS/2"], "sCapHeight", 0) or int(self.ascent * 0.7)
        self.lookups = _kern_lookups(tt)
        self._pairs = {}
        self._fonts = {}

    def font(self, size):
        size = int(round(size))
        if size not in self._fonts:
            self._fonts[size] = ImageFont.truetype(str(self.path), size)
        return self._fonts[size]

    def glyph(self, ch):
        return self.cmap.get(ord(ch), ".notdef")

    def kern(self, left, right):
        pair = (left, right)
        if pair not in self._pairs:
            self._pairs[pair] = sum(_pair_value(lookup, left, right) for lookup in self.lookups)
        return self._pairs[pair]

    def positions(self, text, size):
        """Each character's x offset in pixels, and the whole width."""
        scale = size / self.upem
        glyphs = [self.glyph(ch) for ch in text]
        xs, x = [], 0.0
        for i, g in enumerate(glyphs):
            xs.append(x)
            x += self.advance.get(g, 0) * scale
            if i + 1 < len(glyphs):
                x += self.kern(g, glyphs[i + 1]) * scale
        return xs, x

    def width(self, text, size):
        return self.positions(text, size)[1]

    def draw(self, draw, x, baseline, text, size, fill):
        """text with its left edge at x and its baseline at `baseline`."""
        xs, _ = self.positions(text, size)
        font = self.font(size)
        for ch, dx in zip(text, xs):
            if not ch.isspace():
                draw.text((x + dx, baseline), ch, font=font, fill=fill, anchor="ls")


def _kern_lookups(tt):
    """The pair-positioning subtables of the 'kern' feature, lookup by lookup (each lookup applies its first
    subtable that matches a pair; lookups add up)."""
    if "GPOS" not in tt:
        return []
    gpos = tt["GPOS"].table
    wanted = sorted({i for fr in gpos.FeatureList.FeatureRecord if fr.FeatureTag == "kern"
                     for i in fr.Feature.LookupListIndex})
    lookups = []
    for i in wanted:
        lookup = gpos.LookupList.Lookup[i]
        tables = []
        for st in lookup.SubTable:
            kind = lookup.LookupType
            if kind == 9:
                kind, st = st.ExtensionLookupType, st.ExtSubTable
            if kind == 2:
                tables.append((st, set(st.Coverage.glyphs), {g: n for n, g in enumerate(st.Coverage.glyphs)}))
        if tables:
            lookups.append(tables)
    return lookups


def _x_advance(value):
    return getattr(value, "XAdvance", 0) or 0 if value is not None else 0


def _pair_value(lookup, left, right):
    for st, covered, order in lookup:
        if left not in covered:
            continue
        if st.Format == 1:
            for record in st.PairSet[order[left]].PairValueRecord:
                if record.SecondGlyph == right:
                    return _x_advance(record.Value1)
        elif st.Format == 2:
            c1 = st.ClassDef1.classDefs.get(left, 0) if st.ClassDef1 else 0
            c2 = st.ClassDef2.classDefs.get(right, 0) if st.ClassDef2 else 0
            return _x_advance(st.Class1Record[c1].Class2Record[c2].Value1)
    return 0


def face(weight):
    if weight not in _faces:
        _faces[weight] = Face(weight)
    return _faces[weight]


# ----- Words, lines, fitting -----

def typographic(text):
    """Straight quotes as typographic ones (it's -> it’s)."""
    text = re.sub(r"(\w)'(\w)", "\\1\u2019\\2", text)
    return text.replace("'", "\u2019")


def words(marked):
    """'Answer *out loud*, type' -> [("Answer", False), ("out", True), ("loud,", True), ("type", False)]."""
    out, key = [], False
    for part in re.split(r"(\*)", typographic(marked)):
        if part == "*":
            key = not key
            continue
        for w in part.split():
            out.append((w, key))
    # A word glued to a closing star's punctuation ("loud*," splits as "loud" + ",") goes back onto the word before.
    merged = []
    for w, k in out:
        if merged and re.fullmatch(r"[,.;:!?\u2019]+", w):
            merged[-1] = (merged[-1][0] + w, merged[-1][1])
        else:
            merged.append((w, k))
    return merged


def line_width(f, line, size):
    return f.width(" ".join(w for w, _ in line), size)


def wrap(f, ws, size, width, lines):
    """The most even split of the words into at most `lines` lines that each fit `width` (a break after a comma or
    full stop counts as 10% shorter, so lines end where the sentence pauses), or None."""
    n = len(ws)
    best = None

    def score(option):
        widest = max(line_width(f, line, size) for line in option)
        pauses = all(line[-1][0][-1] in ",.;:!?" for line in option[:-1])
        return widest * (0.9 if pauses and len(option) > 1 else 1.0), widest

    def splits(start, left):
        if left == 1:
            yield [ws[start:]]
            return
        for end in range(start + 1, n - left + 2):
            for rest in splits(end, left - 1):
                yield [ws[start:end]] + rest

    for count in range(1, min(lines, n) + 1):
        for option in splits(0, count):
            rank, widest = score(option)
            if widest <= width and (best is None or rank < best[0]):
                best = (rank, option)
        if best:
            return best[1]
    return None


def fit(f, marked, width, size, smallest, lines):
    """The biggest size from `size` down to `smallest` at which the words fit `lines` lines of `width`: (size, lines)."""
    ws = words(marked)
    s = size
    while s >= smallest:
        option = wrap(f, ws, s, width, lines)
        if option:
            return s, option
        s -= 1
    raise ValueError(f"{marked!r} doesn't fit {lines} line(s) of {width} px even at {smallest} px")


def draw_lines(image, f, lines, size, box, fill, key=None, align="center", valign="center", leading=1.2):
    """Draws wrapped lines (lists of (word, is_key)) inside box (x0, y0, x1, y1). Returns the ink box used."""
    draw = ImageDraw.Draw(image)
    step = size * leading
    block = step * (len(lines) - 1) + f.cap * size / f.upem
    x0, y0, x1, y1 = box
    top = y0 if valign == "top" else (y0 + y1 - block) / 2 if valign == "center" else y1 - block
    first = top + f.cap * size / f.upem
    used = [x1, y0, x0, y1]
    space = f.width(" ", size)
    for i, line in enumerate(lines):
        total = line_width(f, line, size)
        x = x0 if align == "left" else (x0 + x1 - total) / 2 if align == "center" else x1 - total
        baseline = first + i * step
        used = [min(used[0], x), min(used[1], baseline - f.cap * size / f.upem), max(used[2], x + total),
                max(used[3], baseline + 0.22 * size)]
        for w, k in line:
            f.draw(draw, x, baseline, w, size, (key if k and key else fill))
            x += f.width(w, size) + space
    return tuple(int(round(v)) for v in used)


def worst_contrast(image, box, colours, pad=18):
    """What guard() measures, before any scrim: for each colour, text of that colour against the worst 5% of the
    pixels in box (and pad around it). {colour: ratio}."""
    x0, y0, x1, y1 = (max(0, box[0] - pad), max(0, box[1] - pad), min(image.size[0], box[2] + pad),
                      min(image.size[1], box[3] + pad))
    behind = luminance(np.asarray(image.convert("RGB").crop((x0, y0, x1, y1)), dtype=np.float64))
    return {c: float(np.percentile(contrast(luminance(np.array(colour(c), dtype=np.float64)), behind), 5))
            for c in colours}


def guard(image, box, colours, at_least=7.0, scrim="navy", most=0.85, pad=18, radius=24):
    """Makes sure text of these colours, to be drawn in box, has at least 7:1 against the worst 5% of the pixels
    behind it: if not, darkens that area with a rounded navy scrim (up to `most` opaque) until it does. Returns the
    scrim's opacity (0 when none was needed); raises if even `most` isn't enough."""
    x0, y0, x1, y1 = (max(0, box[0] - pad), max(0, box[1] - pad), min(image.size[0], box[2] + pad),
                      min(image.size[1], box[3] + pad))
    region = np.asarray(image.convert("RGB").crop((x0, y0, x1, y1)), dtype=np.float64)
    tint = np.array(colour(scrim), dtype=np.float64)
    lums = [luminance(np.array(colour(c), dtype=np.float64)) for c in colours]
    for step in range(0, int(most * 20) + 1):
        a = step / 20
        behind = luminance(region * (1 - a) + tint * a)
        worst = min(float(np.percentile(contrast(l, behind), 5)) for l in lums)
        if worst >= at_least:
            if a > 0:
                layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
                ImageDraw.Draw(layer).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius,
                                                        fill=tuple(int(v) for v in tint) + (int(round(a * 255)),))
                image.alpha_composite(layer) if image.mode == "RGBA" else image.paste(
                    Image.alpha_composite(image.convert("RGBA"), layer).convert(image.mode))
            return a
    raise ValueError(f"text in {box} can't reach {at_least}:1 even with a {most:.0%} scrim")
