"""An icon concept's emblem on its own, on a transparent background: what every icon export is cut from.

--method auto tries, in order:
  local   cut out here, for nothing and exactly as drawn: the concept's background (navy, maybe with a soft glow) is
          estimated as a smooth field, and every pixel read as a mix of that background and one of the emblem's
          colours. Used when that explains the picture well (a flat-colour emblem on a smooth background).
  edit    an edit of the concept with background "transparent", by a model the probe saw make one; accepted with at
          least 20% of its pixels fully transparent and its corners clear. (A model redraws as it edits, so details
          can shift: the report gives how closely its outline matches the concept's.)
  keyed   an edit onto flat magenta (#FF00FF), keyed out here.
Each result is finished the same way: put on flat navy and pulled off it again, every pixel snapped to the brand's
emblem colours (gold and white, plus any other colour the emblem really has), specks removed. If nothing works, the
concept is marked "vector redraw needed" in the index and the emblem has to be drawn by hand.
"""
from collections import deque

import numpy as np
from PIL import Image

from . import api
from .brand import brand, colour, now, prompts, rel
from .cache import Budget, BudgetExceeded, Entry, concept, fetch, find, lookup, pixels_hash, store_local, \
    update_concept
from .compose import alpha_bbox, hex_of, kmeans

LAYER_VERSION = 1           # part of a local layer's key: bump it when the cutting changes


def emblem_colours():
    return [np.array(colour(c), dtype=np.float64) for c in brand()["emblemColours"]]


def pull(rgb, bg, colours, cutoff=0.1, solid=0.92):
    """Each pixel as a mix of the background and one emblem colour (an edge, or the emblem itself), or as a mix of
    two emblem colours (where gold meets white). Returns alpha (0-1), the pixel's colour without the background
    (snapped to the emblem colours, or their mix along a gold-white edge) and the residual: how far, in levels, the
    pixel is from the best mix (a big residual means the picture isn't a flat emblem on that background)."""
    h, w, _ = rgb.shape
    bg = np.broadcast_to(np.asarray(bg, dtype=np.float64), rgb.shape)
    d = rgb - bg
    best_r = np.full((h, w), np.inf)
    alpha = np.zeros((h, w))
    out = np.zeros((h, w, 3))
    for c in colours:
        v = c - bg
        a = np.clip(np.sum(d * v, axis=2) / np.maximum(np.sum(v * v, axis=2), 1e-6), 0, 1)
        r = np.linalg.norm(d - a[..., None] * v, axis=2)
        better = r < best_r
        best_r = np.where(better, r, best_r)
        alpha = np.where(better, np.clip((a - cutoff) / (solid - cutoff), 0, 1), alpha)
        out = np.where(better[..., None], c, out)
    for i in range(len(colours)):
        for j in range(i + 1, len(colours)):
            ci, cj = colours[i], colours[j]
            v = cj - ci
            t = np.clip(np.sum((rgb - ci) * v, axis=2) / max(float(np.sum(v * v)), 1e-6), 0, 1)
            mix = ci + t[..., None] * v
            r = np.linalg.norm(rgb - mix, axis=2)
            better = r < best_r - 0.5
            best_r = np.where(better, r, best_r)
            alpha = np.where(better, 1.0, alpha)
            out = np.where(better[..., None], mix, out)
    return alpha, out, best_r


def field(rgb, colours, cell=32):
    """The background behind the emblem as a smooth field: the median of the clearly-background pixels in each cell of
    a coarse grid, the cells the emblem covers filled in from their neighbours, smoothed and scaled back up."""
    h, w, _ = rgb.shape
    m = max(2, int(0.04 * min(w, h)))
    border = np.concatenate([rgb[:m].reshape(-1, 3), rgb[-m:].reshape(-1, 3), rgb[:, :m].reshape(-1, 3),
                             rgb[:, -m:].reshape(-1, 3)])
    bg0 = np.median(border, axis=0)
    far = np.min(np.stack([np.linalg.norm(rgb - c, axis=2) for c in colours]), axis=0) > 120
    cand = (np.linalg.norm(rgb - bg0, axis=2) < 90) & far
    gh, gw = -(-h // cell), -(-w // cell)
    grid = np.full((gh, gw, 3), np.nan)
    for gy in range(gh):
        for gx in range(gw):
            ys, xs = slice(gy * cell, (gy + 1) * cell), slice(gx * cell, (gx + 1) * cell)
            pix = rgb[ys, xs][cand[ys, xs]]
            if len(pix) > 0.25 * cell * cell:
                grid[gy, gx] = np.median(pix, axis=0)
    while np.isnan(grid).any():
        known = ~np.isnan(grid[..., 0])
        if not known.any():
            grid[:] = bg0
            break
        filled = grid.copy()
        for gy, gx in zip(*np.nonzero(~known)):
            near = [grid[y, x] for y, x in ((gy - 1, gx), (gy + 1, gx), (gy, gx - 1), (gy, gx + 1))
                    if 0 <= y < gh and 0 <= x < gw and known[y, x]]
            if near:
                filled[gy, gx] = np.mean(near, axis=0)
        grid = filled
    for _ in range(2):
        p = np.pad(grid, ((1, 1), (1, 1), (0, 0)), mode="edge")
        grid = sum(p[dy:dy + gh, dx:dx + gw] for dy in range(3) for dx in range(3)) / 9.0
    chans = [np.asarray(Image.fromarray(grid[..., i].astype(np.float32), "F").resize((w, h), Image.BILINEAR))
             for i in range(3)]
    return np.dstack(chans).astype(np.float64)


def extra_colours(rgb, alpha, residual, colours):
    """Colours the emblem really has besides the brand's (an orange, a dark outline): solid pixels no mix explains."""
    off = (alpha > 0.9) & (residual > 40)
    if off.sum() < 0.03 * max(1, (alpha > 0.5).sum()):
        return []
    centres, labels = kmeans(rgb[off][::max(1, int(off.sum()) // 20000)], 2)
    return [c for i, c in enumerate(centres) if np.mean(labels == i) > 0.2]


def components(mask):
    """The separate blobs of a boolean mask (4-connected): a list of flat-index arrays, one per blob. (No scipy here,
    so a plain flood fill; about a second for a 1024-pixel emblem.)"""
    h, w = mask.shape
    flat = mask.ravel().tolist()
    seen = bytearray(h * w)
    blobs = []
    for start in np.flatnonzero(mask).tolist():
        if seen[start]:
            continue
        queue, members = deque([start]), [start]
        seen[start] = 1
        while queue:
            i = queue.popleft()
            x = i % w
            for j in (i - w if i >= w else -1, i + w if i + w < h * w else -1, i - 1 if x else -1,
                      i + 1 if x + 1 < w else -1):
                if j >= 0 and flat[j] and not seen[j]:
                    seen[j] = 1
                    queue.append(j)
                    members.append(j)
        blobs.append(np.array(members, dtype=np.int64))
    return blobs


def specks_removed(alpha, smallest=0.002):
    """alpha with every separate blob smaller than `smallest` of the emblem's area taken out."""
    solid = alpha > 0.5
    total = int(solid.sum())
    if total == 0:
        return alpha
    x0, y0, x1, y1 = _box(solid)
    sub = solid[y0:y1, x0:x1]
    small = [b for b in components(sub) if len(b) < smallest * total]
    if not small:
        return alpha
    out = alpha.copy()
    gone = np.zeros(sub.size, dtype=bool)
    gone[np.concatenate(small)] = True
    gone = gone.reshape(sub.shape)
    # Take the blob's soft edge too: everything within 2 pixels of it that isn't part of a kept blob.
    from .compose import _dilate
    grown = _dilate(gone, 2) & ~(sub & ~gone)
    region = out[y0:y1, x0:x1]
    region[grown] = 0.0
    return out


def _box(mask):
    ys, xs = np.nonzero(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def finish(rgba, colours=None):
    """Any cut-out made clean: put on flat navy and pulled off it again (so the navy and glow inside the emblem become
    see-through too), colours snapped to the emblem's, specks removed. Returns (RGBA image, report)."""
    navy = np.array(colour("navy"), dtype=np.float64)
    arr = np.asarray(rgba.convert("RGBA"), dtype=np.float64)
    a = arr[..., 3:4] / 255.0
    rgb = arr[..., :3] * a + navy * (1 - a)
    colours = colours or emblem_colours()
    alpha, col, residual = pull(rgb, navy, colours)
    extras = extra_colours(rgb, alpha, residual, colours)
    if extras:
        colours = colours + extras
        alpha, col, residual = pull(rgb, navy, colours)
    alpha = specks_removed(alpha)
    out = np.dstack([col, alpha * 255.0])
    image = Image.fromarray(np.clip(np.round(out), 0, 255).astype(np.uint8), "RGBA")
    return image, {"colours": [hex_of(c) for c in colours], "extra": [hex_of(c) for c in extras]}


def cut_local(image):
    """The local method: (RGBA, report), with report["ok"] saying whether the picture was explained well enough."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    colours = emblem_colours()
    bg = field(rgb, colours)
    alpha, col, residual = pull(rgb, bg, colours)
    extras = extra_colours(rgb, alpha, residual, colours)
    if extras:
        colours = colours + extras
        alpha, col, residual = pull(rgb, bg, colours)
    edge = residual[alpha < 0.5]
    h, w = alpha.shape
    corners = max(alpha[:8, :8].max(), alpha[:8, -8:].max(), alpha[-8:, :8].max(), alpha[-8:, -8:].max())
    cover = float((alpha > 0.5).mean())
    report = {"method": "local", "residualMedian": round(float(np.median(edge)), 1),
              "residualP99": round(float(np.percentile(edge, 99)), 1), "cover": round(cover, 3),
              "cornersClear": bool(corners == 0), "extra": [hex_of(c) for c in extras]}
    report["ok"] = bool(report["residualMedian"] < 6 and report["residualP99"] < 30 and report["cornersClear"]
                        and 0.03 <= cover <= 0.75)
    rgba = Image.fromarray(np.clip(np.round(np.dstack([col, alpha * 255.0])), 0, 255).astype(np.uint8), "RGBA")
    return rgba, report


def likeness(concept_image, layer):
    """How closely a layer's outline matches the concept's emblem (intersection over union, after lining up their
    bounding boxes): 1.0 is the same shape."""
    rgb = np.asarray(concept_image.convert("RGB"), dtype=np.float64)
    bg = field(rgb, emblem_colours())
    a, _, _ = pull(rgb, bg, emblem_colours())
    mine = a > 0.5
    x0, y0, x1, y1 = _box(mine)
    theirs = layer.crop(alpha_bbox(layer)).getchannel("A").resize((x1 - x0, y1 - y0), Image.BILINEAR)
    t = np.asarray(theirs) > 127
    m = mine[y0:y1, x0:x1]
    return round(float((m & t).sum() / max(1, (m | t).sum())), 3)


def _accept_transparent(image):
    if image.mode != "RGBA":
        return False, "no alpha channel"
    a = np.asarray(image.getchannel("A"))
    clear = float((a == 0).mean())
    corners = max(a[:8, :8].max(), a[:8, -8:].max(), a[-8:, :8].max(), a[-8:, -8:].max()) == 0
    ok = clear >= 0.2 and corners
    return ok, f"{clear:.0%} fully transparent, corners {'clear' if corners else 'not clear'}"


def _edit(cid, c, image, what, model, budget, force):
    """An edit of the concept: what = "edit" (transparent background) or "keyed" (flat magenta)."""
    p = prompts("icon")
    from .concepts import choose_model, png_bytes, uses_fidelity
    model = choose_model(model, transparent=(what == "edit"))
    if not model:
        return None, {"method": what, "ok": False, "why": "no model the probe saw make a transparent background"}
    req = {"endpoint": "images/edits", "model": model, "prompt": p["layer" if what == "edit" else "keyed"],
           "size": "1024x1024", "quality": "high", "background": "transparent" if what == "edit" else "opaque",
           "output_format": "png", "n": 1, "inputs": [pixels_hash(image)], "variant": 0}
    if uses_fidelity(model):
        req["input_fidelity"] = "high"
    if force:
        while lookup(req) is not None:
            req["variant"] += 1
    entry, new = fetch(req, budget, inputs=[png_bytes(image)], store="png", label=f"layer {what} {cid}")
    got = entry.image()
    report = {"method": what, "model": model, "key": entry.key, "new": new, "cost": entry.meta["cost_usd"]}
    if what == "edit":
        ok, why = _accept_transparent(got)
        report.update(ok=ok, why=why)
        return (got if ok else None), report
    rgb = np.asarray(got.convert("RGB"), dtype=np.float64)
    magenta = np.array(colour("keyColour"), dtype=np.float64)
    border = np.concatenate([rgb[:16].reshape(-1, 3), rgb[-16:].reshape(-1, 3)])
    if np.median(np.linalg.norm(border - magenta, axis=1)) > 40:
        report.update(ok=False, why="the background isn't flat magenta")
        return None, report
    alpha, col, residual = pull(rgb, magenta, emblem_colours() + [np.array(colour("navy"), dtype=np.float64)])
    keyed = Image.fromarray(np.clip(np.round(np.dstack([col, alpha * 255.0])), 0, 255).astype(np.uint8), "RGBA")
    report.update(ok=True, why="keyed out of magenta")
    return keyed, report


def run_layers(cid, method="auto", model=None, budget_limit=None, force=False):
    c = concept(cid)
    if c["kind"] != "icon":
        raise SystemExit(f"{cid} isn't an icon concept")
    if c.get("layer", {}).get("key") and not force and method == "auto":
        print(f"{cid}: has its layer already ({c['layer']['method']}); --force to cut it again")
        return emblem_of(cid)
    image = Entry(c["key"]).image(c.get("image", 0)).convert("RGB")
    budget = Budget(budget_limit)
    order = ["local", "edit", "keyed"] if method == "auto" else [method]
    tried = []
    for how in order:
        try:
            if how == "local":
                cut, report = cut_local(image)
                if not report["ok"]:
                    tried.append(report)
                    print(f"  local: not clean enough (residual median {report['residualMedian']}, "
                          f"99th percentile {report['residualP99']}, cover {report['cover']:.0%}, corners "
                          f"{'clear' if report['cornersClear'] else 'not clear'})")
                    if method == "auto":
                        continue
            else:
                cut, report = _edit(cid, c, image, how, model, budget, force)
                if cut is None:
                    tried.append(report)
                    print(f"  {how}: not usable ({report.get('why')})")
                    continue
        except BudgetExceeded as e:
            print(f"  {how}: stopped: {e}")
            tried.append({"method": how, "ok": False, "why": str(e)})
            break
        except api.ApiError as e:
            print(f"  {how}: failed: {e}")
            tried.append({"method": how, "ok": False, "why": str(e)})
            if e.status in (401, 403):
                break
            continue
        layer, finished = finish(cut)
        report.update(finished)
        report["likeness"] = likeness(image, layer)
        req = {"endpoint": "local/layer", "version": LAYER_VERSION, "concept": c["key"], "method": how,
               "source": report.get("key", c["key"])}
        entry = store_local(req, layer)
        update_concept(cid, layer={"key": entry.key, "method": how, "made": now(), "likeness": report["likeness"],
                                   "colours": report["colours"], "source": report.get("key")})
        print(f"{cid}: layer cut ({how}; outline matches the concept {report['likeness']:.0%}; colours "
              f"{', '.join(report['colours'])}) -> {rel(entry.path())}")
        if budget.calls:
            print(budget.summary())
        return layer
    update_concept(cid, layer={"method": "vector redraw needed", "made": now(), "tried": tried})
    print(f"{cid}: no clean layer; marked \"vector redraw needed\" (the emblem has to be drawn by hand)")
    if budget.calls:
        print(budget.summary())
    return None


def emblem_of(cid):
    """A concept's finished layer (RGBA, 1024), or None if it hasn't been cut."""
    layer = concept(cid).get("layer") or {}
    entry = find(layer["key"]) if layer.get("key") else None
    return entry.image() if entry else None
