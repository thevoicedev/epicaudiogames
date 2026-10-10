"""Pixels: the brand background, the launcher and home-screen icon shapes, placing the emblem on a canvas, WCAG
contrast, colour-vision simulation and the review sheet's wallpapers.

Everything here is deterministic (no random numbers, no clock): an export run twice, here or on the Mac, gives the same
pixels. Shapes are drawn with 4x4 supersampling for smooth edges.
"""
import numpy as np
from PIL import Image

from .brand import brand, colour

# Machado, Oliveira and Fernandes (2009), severity 1.0, applied to linear RGB.
MACHADO = {
    "protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


# ----- Colour -----

def to_linear(c):
    """sRGB values (0-255, any shape) to linear light (0-1)."""
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(lin):
    lin = np.clip(lin, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055) * 255.0


def luminance(rgb):
    """WCAG relative luminance of sRGB colours (..., 3) in 0-255."""
    lin = to_linear(rgb)
    return lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722


def contrast(l1, l2):
    """WCAG contrast ratio between two luminances (arrays broadcast)."""
    hi, lo = np.maximum(l1, l2), np.minimum(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def ratio(c1, c2):
    return float(contrast(luminance(np.array(c1)), luminance(np.array(c2))))


def hex_of(rgb):
    return "#{:02X}{:02X}{:02X}".format(*(int(round(v)) for v in rgb[:3]))


# ----- Noise and the background -----

def hash_noise(w, h, salt=0):
    """Deterministic white noise in [0, 1), the same on every machine (an integer hash of x and y, not a seeded
    generator whose stream could change between numpy versions)."""
    y, x = np.mgrid[0:h, 0:w].astype(np.uint64)
    v = (x * np.uint64(0x9E3779B1) + y * np.uint64(0x85EBCA77) + np.uint64(salt * 0xC2B2AE3D + 0x27D4EB2F)) \
        & np.uint64(0xFFFFFFFF)
    for _ in range(3):
        v ^= v >> np.uint64(15)
        v = (v * np.uint64(0x2C1B3C6D)) & np.uint64(0xFFFFFFFF)
        v ^= v >> np.uint64(12)
        v = (v * np.uint64(0x297A2D39)) & np.uint64(0xFFFFFFFF)
        v ^= v >> np.uint64(15)
    return v.astype(np.float64) / 4294967296.0


def background(size, inner=None, outer=None, reach=None):
    """The brand background: a radial gradient from inner (the centre) to outer (reached at `reach` of the way to the
    corners), eased, with triangular noise of one level so it doesn't band. RGB."""
    b = brand()["background"]
    inner = np.array(colour(inner or b["inner"]), dtype=np.float64)
    outer = np.array(colour(outer or b["outer"]), dtype=np.float64)
    reach = reach or b["reach"]
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    d = np.hypot(x + 0.5 - w / 2, y + 0.5 - h / 2) / (reach * np.hypot(w / 2, h / 2))
    t = np.clip(d, 0, 1)
    t = t * t * (3 - 2 * t)
    rgb = inner * (1 - t[..., None]) + outer * t[..., None]
    rgb += (hash_noise(w, h, 1) + hash_noise(w, h, 2) - 1.0)[..., None]
    return Image.fromarray(np.clip(np.round(rgb), 0, 255).astype(np.uint8), "RGB")


# ----- Shapes -----

def _coverage(size, inside, ss=4):
    """A shape's coverage (L mask) from inside(u, v) on coordinates -1..1, supersampled ss x ss per pixel."""
    w, h = size
    acc = np.zeros((h, w), dtype=np.float64)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    for i in range(ss):
        for j in range(ss):
            u = (xs + (j + 0.5) / ss) / w * 2 - 1
            v = (ys + (i + 0.5) / ss) / h * 2 - 1
            acc += inside(u, v)
    return Image.fromarray(np.round(acc / (ss * ss) * 255).astype(np.uint8), "L")


def superellipse(size, n=5.0):
    """Close to the iOS icon shape (its continuous-corner squircle) at n = 5."""
    return _coverage(size, lambda u, v: (np.abs(u) ** n + np.abs(v) ** n) <= 1.0)


def circle(size):
    return _coverage(size, lambda u, v: u * u + v * v <= 1.0)


def rounded(size, tl, tr=None, br=None, bl=None, inset=0.0):
    """A rounded rectangle; corner radii as a share of the half-size (1.0 makes that side a semicircle)."""
    tr = tl if tr is None else tr
    br = tl if br is None else br
    bl = tl if bl is None else bl
    e = 1.0 - inset

    def inside(u, v):
        ok = (np.abs(u) <= e) & (np.abs(v) <= e)
        for r, sx, sy in ((tl, -1, -1), (tr, 1, -1), (br, 1, 1), (bl, -1, 1)):
            if r <= 0:
                continue
            rr = r * e
            cx, cy = sx * (e - rr), sy * (e - rr)
            corner = (sx * u > sx * cx) & (sy * v > sy * cy)
            ok &= ~corner | ((u - cx) ** 2 + (v - cy) ** 2 <= rr * rr)
        return ok

    return _coverage(size, inside)


def shapes(size):
    """The home-screen shapes the review sheet tries: iOS, and the Android launcher masks."""
    return {"iOS": superellipse(size, 5.0), "circle": circle(size), "squircle": superellipse(size, 3.6),
            "teardrop": rounded(size, 1.0, 1.0, 0.3, 1.0), "rounded square": rounded(size, 0.6)}


def masked(image, mask):
    """image with mask applied to its alpha (RGBA)."""
    out = image.convert("RGBA")
    a = np.asarray(out.getchannel("A"), dtype=np.float64) * np.asarray(mask, dtype=np.float64) / 255.0
    out.putalpha(Image.fromarray(np.round(a).astype(np.uint8), "L"))
    return out


# ----- The emblem on a canvas -----

def alpha_bbox(image, threshold=8):
    a = np.asarray(image.getchannel("A"))
    ys, xs = np.nonzero(a > threshold)
    if len(xs) == 0:
        raise ValueError("the emblem is empty")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def trimmed(emblem):
    """The emblem cropped to what's visible of it."""
    return emblem.crop(alpha_bbox(emblem))


def reach(emblem, threshold=32):
    """How far the emblem's furthest visible pixel is from its centre (in its own pixels)."""
    a = np.asarray(emblem.getchannel("A"))
    h, w = a.shape
    ys, xs = np.nonzero(a > threshold)
    return float(np.max(np.hypot(xs + 0.5 - w / 2, ys + 0.5 - h / 2)))


def place(emblem, size, longer, radius=None):
    """The emblem (already trimmed) centred on a transparent canvas of `size`, its longer side `longer` pixels, or
    smaller so that no visible pixel is further than `radius` from the centre. Returns (image, scale)."""
    w, h = emblem.size
    scale = longer / max(w, h)
    if radius:
        scale = min(scale, radius / reach(emblem))
    sw, sh = max(1, round(w * scale)), max(1, round(h * scale))
    small = emblem.resize((sw, sh), Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(small, ((size[0] - sw) // 2, (size[1] - sh) // 2))
    return canvas, scale


def on(background_image, layer):
    """A layer composited over a background (both the same size); RGBA out."""
    out = background_image.convert("RGBA")
    out.alpha_composite(layer)
    return out


def grey(image):
    """The image's luminance as grey (in sRGB), alpha kept: the tinted iOS icon and the grayscale check."""
    rgba = image.convert("RGBA")
    arr = np.asarray(rgba, dtype=np.float64)
    g = to_srgb(luminance(arr[..., :3]))
    out = np.dstack([g, g, g, arr[..., 3]])
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def simulate(image, kind):
    """How the image looks with a colour-vision deficiency (Machado 2009), or as grey."""
    if kind == "grayscale":
        return grey(image)
    rgba = image.convert("RGBA")
    arr = np.asarray(rgba, dtype=np.float64)
    lin = to_linear(arr[..., :3]) @ np.array(MACHADO[kind]).T
    out = np.dstack([to_srgb(lin), arr[..., 3]])
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


# ----- Wallpapers for the review sheet -----

def wallpaper(kind, size):
    """A plain light, plain dark or busy home screen behind the icons (deterministic)."""
    w, h = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    if kind == "light":
        base = np.array([236, 238, 244.0]) + (y / h)[..., None] * np.array([-14, -10, -4.0])
    elif kind == "dark":
        base = np.array([18, 18, 22.0]) + (y / h)[..., None] * np.array([6, 4, 12.0])
    else:
        # Big soft blobs of saturated colour over stripes: the worst case, a holiday photo behind the icons.
        base = np.zeros((h, w, 3))
        blobs = [(0.2, 0.25, (230, 120, 40)), (0.75, 0.2, (40, 160, 220)), (0.5, 0.7, (250, 210, 60)),
                 (0.1, 0.85, (60, 180, 90)), (0.9, 0.8, (200, 60, 120)), (0.55, 0.35, (245, 245, 235))]
        weight = np.zeros((h, w))
        for bx, by, c in blobs:
            g = np.exp(-(((x / w - bx) ** 2 + (y / h - by) ** 2) / 0.03))
            base += g[..., None] * np.array(c, dtype=np.float64)
            weight += g
        base = base / np.maximum(weight, 1e-6)[..., None]
        stripes = (np.sin((x + y) / 7.0) > 0.6)[..., None]
        base = np.where(stripes, base * 0.75, base)
    return Image.fromarray(np.clip(np.round(base), 0, 255).astype(np.uint8), "RGB")


def checker(size, cell=12):
    w, h = size
    y, x = np.mgrid[0:h, 0:w]
    v = np.where(((x // cell) + (y // cell)) % 2 == 0, 200, 150).astype(np.uint8)
    return Image.fromarray(np.dstack([v, v, v]), "RGB")


# ----- What a full-bleed concept is made of -----

def kmeans(points, k, iters=12):
    """Deterministic k-means on (n, 3) colours: the first centre is the most common colour bucket, each next one the
    point furthest from the centres so far."""
    pts = np.asarray(points, dtype=np.float64)
    if len(pts) == 0:
        return np.zeros((0, 3)), np.zeros(0, dtype=int)
    k = min(k, len(pts))
    buckets = np.round(pts / 16).astype(int)
    _, inv, counts = np.unique(buckets, axis=0, return_inverse=True, return_counts=True)
    centres = [pts[inv.ravel() == np.argmax(counts)].mean(axis=0)]
    while len(centres) < k:
        d = np.min(np.stack([np.sum((pts - c) ** 2, axis=1) for c in centres]), axis=0)
        if d.max() < 900:            # every colour within 30 levels of a centre: no more clusters
            break
        centres.append(pts[int(np.argmax(d))])
    centres = np.array(centres)
    for _ in range(iters):
        labels = np.argmin(np.stack([np.sum((pts - c) ** 2, axis=1) for c in centres]), axis=0)
        for i in range(len(centres)):
            if np.any(labels == i):
                centres[i] = pts[labels == i].mean(axis=0)
    labels = np.argmin(np.stack([np.sum((pts - c) ** 2, axis=1) for c in centres]), axis=0)
    return centres, labels


def anatomy(image):
    """A full-bleed concept's background and emblem: the background colour (its border), the emblem's mask, its
    colours with their share of the emblem and their contrast against the background right around the emblem, the
    emblem's size and how much of the square it covers."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    h, w, _ = rgb.shape
    m = max(2, int(0.04 * min(w, h)))
    border = np.concatenate([rgb[:m].reshape(-1, 3), rgb[-m:].reshape(-1, 3), rgb[:, :m].reshape(-1, 3),
                             rgb[:, -m:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    lum = luminance(rgb)
    lbg = float(luminance(bg))
    emblem = (contrast(lum, lbg) >= 1.6) | (np.linalg.norm(rgb - bg, axis=2) >= 110)
    out = {"background": hex_of(bg), "colours": [], "fill": 0.0, "extent": 0.0}
    if not emblem.any():
        return out
    ys, xs = np.nonzero(emblem)
    out["fill"] = round(float(emblem.mean()), 3)
    out["extent"] = round(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) / max(w, h), 3)
    # The background right next to the emblem (a glow behind it can make it lighter than the border).
    near = _dilate(emblem, max(3, w // 40)) & ~emblem
    lnear = float(np.percentile(lum[near], 90)) if near.any() else lbg
    solid = emblem & ~(_dilate(~emblem, 2))
    pts = rgb[solid] if solid.any() else rgb[emblem]
    step = max(1, len(pts) // 40000)
    centres, labels = kmeans(pts[::step], 4)
    for i, c in enumerate(centres):
        share = float(np.mean(labels == i))
        if share < 0.02:
            continue
        out["colours"].append({"colour": hex_of(c), "share": round(share, 3),
                               "contrast": round(float(contrast(luminance(c), lnear)), 2)})
    out["colours"].sort(key=lambda c: -c["share"])
    out["minContrast"] = min((c["contrast"] for c in out["colours"]), default=None)
    return out


def _dilate(mask, r):
    """A boolean mask grown by r pixels (a square neighbourhood, via Pillow's max filter)."""
    from PIL import ImageFilter
    img = Image.fromarray((mask * 255).astype(np.uint8), "L")
    size = 2 * r + 1
    while size > 1:
        step = min(size, 9) if min(size, 9) % 2 == 1 else min(size, 9) - 1
        img = img.filter(ImageFilter.MaxFilter(step))
        size -= step - 1
    return np.asarray(img) > 127
