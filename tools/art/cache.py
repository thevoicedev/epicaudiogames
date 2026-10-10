"""Every image the tool pays for, kept for good in tools/cache/art/ (committed, like the voices in tools/cache/), so
nothing is generated twice, and what each one cost.

  <key[:2]>/<key>/request.json   the request as sent (input images as their sha256); the key is the sha256 of it
  <key[:2]>/<key>/meta.json      when, how long, the model's token usage, what it cost, its revised prompt; never the key
  <key[:2]>/<key>/0.webp|0.png   the image (concepts and probes as WebP at quality 90, alpha kept lossless; paid
                                 layer edits as PNG, as received; layers cut here as PNG)
  ledger.jsonl                   one line per paid call: when, which model, the usage and the cost
  index.json                     the concepts by id (icon-01, feature-01, ...): which cached image, which motif

A request's "variant" (0 unless --force asked for another take) is part of the key and never sent. Budget stops a
run before a call that would take it over its limit, or the ledger over brand.json's overall limit.
"""
import base64
import hashlib
import io
import json
import threading
import time

from PIL import Image

from . import api
from .brand import CACHE, brand, now, read_json, write_bytes, write_json

LEDGER = CACHE / "ledger.jsonl"
INDEX = CACHE / "index.json"

# Output tokens of one 1024x1024 image, from OpenAI's image generation guide (2026-10-09): the published counts for
# the gpt-image-1 family, and gpt-image-2's worked back from its per-image prices at $30 a million. The guide gives no
# numbers for xhigh and max (2.5 only), so they're guessed high (2x and 4x high) to keep the budget guard on the safe
# side; once a model has been used, the ledger's real costs replace these guesses.
SQUARE_TOKENS = {
    "gpt-image-1": {"low": 272, "medium": 1056, "high": 4160},
    "gpt-image-2": {"low": 200, "medium": 1767, "high": 7034, "xhigh": 14068, "max": 28136},
}
INPUT_IMAGE_TOKENS = 6500          # one input image of an edit at high fidelity (a guess on the high side)

_lock = threading.RLock()


class BudgetExceeded(RuntimeError):
    pass


def canonical(request):
    return json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def key_of(request):
    return hashlib.sha256(canonical(request).encode("utf-8")).hexdigest()


def folder(key):
    return CACHE / key[:2] / key


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pixels_hash(image):
    """An input image's identity in a request: the sha256 of its pixels (not of a PNG file, whose bytes depend on
    the machine's zlib), so the same edit is found in the cache on Windows and on the Mac."""
    h = hashlib.sha256(f"{image.mode} {image.size[0]}x{image.size[1]}\n".encode())
    h.update(image.tobytes())
    return h.hexdigest()


class Entry:
    """One cached request: its request, its meta and its image files."""

    def __init__(self, key):
        self.key = key
        self.dir = folder(key)
        self.request = read_json(self.dir / "request.json")
        self.meta = read_json(self.dir / "meta.json")

    def paths(self):
        return sorted(p for p in self.dir.iterdir() if p.stem.isdigit() and p.suffix in (".png", ".webp"))

    def path(self, i=0):
        for p in self.paths():
            if p.stem == str(i):
                return p
        raise FileNotFoundError(f"{self.dir}: no image {i}")

    def image(self, i=0):
        with Image.open(self.path(i)) as im:
            im.load()
            return im.convert("RGBA") if im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info \
                else im.convert("RGB")


def find(key):
    if (folder(key) / "meta.json").exists():
        return Entry(key)
    return None


def lookup(request):
    return find(key_of(request))


# ----- Prices -----

def prices(model):
    table = brand()["prices"]
    if model in table:
        return table[model]
    # An unknown model is charged at the dearest known rates, so the guard never under-counts.
    return {"textIn": 5.0, "imageIn": 10.0, "imageOut": 40.0, "textOut": 10.0}


def cost(model, usage):
    """US dollars for one response, from its usage (tokens) and brand.json's prices."""
    if not usage:
        return None
    p = prices(model)
    inp = usage.get("input_tokens_details") or {}
    out = usage.get("output_tokens_details") or {}
    text_in = inp.get("text_tokens", usage.get("input_tokens", 0) if not inp else 0)
    image_in = inp.get("image_tokens", 0)
    image_out = out.get("image_tokens", usage.get("output_tokens", 0) if not out else 0)
    text_out = out.get("text_tokens", 0)
    return round((text_in * p["textIn"] + image_in * p["imageIn"] + image_out * p["imageOut"]
                  + text_out * p.get("textOut", p["textIn"])) / 1e6, 6)


def _pixels(size):
    try:
        w, h = (int(x) for x in str(size).split("x"))
        return w * h
    except ValueError:
        return 1536 * 1024          # "auto": assume the biggest standard size


def estimate(request):
    """What a request will probably cost: the most a matching request has cost before (from the ledger), else the
    token table above, with every input image counted at high fidelity."""
    model, quality, n = request["model"], request.get("quality", "auto"), request.get("n", 1)
    seen = [e["cost_usd"] / max(1, e.get("n", 1)) for e in ledger()
            if e.get("model") == model and e.get("quality") == quality and e.get("size") == request.get("size")
            and e.get("endpoint") == request["endpoint"] and e.get("cost_usd") is not None]
    if seen:
        return round(max(seen) * 1.1 * n, 4)
    family = "gpt-image-2" if model.startswith("gpt-image-2") else "gpt-image-1"
    table = SQUARE_TOKENS[family]
    tokens = table.get(quality if quality != "auto" else "high", max(table.values()))
    out_tokens = tokens * _pixels(request.get("size", "1024x1024")) / (1024 * 1024) * n
    p = prices(model)
    text_tokens = len(request.get("prompt", "")) / 3.5
    image_in = INPUT_IMAGE_TOKENS * len(request.get("inputs", []))
    return round((out_tokens * p["imageOut"] + text_tokens * p["textIn"] + image_in * p["imageIn"]) / 1e6, 4)


# ----- The ledger and the budget -----

def ledger():
    if not LEDGER.exists():
        return []
    out = []
    for line in LEDGER.read_text(encoding="utf-8").splitlines():
        if line.strip():
            out.append(json.loads(line))
    return out


def ledger_total():
    return round(sum(e.get("cost_usd") or 0 for e in ledger()), 4)


def _log(entry):
    with _lock:
        LEDGER.parent.mkdir(parents=True, exist_ok=True)
        with open(LEDGER, "a", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n")


class Budget:
    """A run's spending limit (US dollars). reserve() before a call (it raises BudgetExceeded instead of going over),
    settle() after it with what it really cost."""

    def __init__(self, limit=None):
        b = brand()["budget"]
        self.limit = float(limit if limit is not None else b["run"])
        self.total = float(b["total"])
        self.before = ledger_total()
        self.spent = 0.0
        self.reserved = 0.0
        self.calls = 0

    def reserve(self, amount, what):
        with _lock:
            if self.spent + self.reserved + amount > self.limit + 1e-9:
                raise BudgetExceeded(f"{what} would cost about ${amount:.3f}, and this run has spent "
                                     f"${self.spent:.3f} of its ${self.limit:.2f} budget (--budget)")
            if self.before + self.spent + self.reserved + amount > self.total + 1e-9:
                raise BudgetExceeded(f"{what} would take the ledger past brand.json's overall budget of "
                                     f"${self.total:.2f} (spent so far: ${self.before + self.spent:.3f})")
            self.reserved += amount

    def settle(self, reserved, actual, paid=True):
        with _lock:
            self.reserved -= reserved
            self.spent += actual
            self.calls += 1 if paid else 0

    def summary(self):
        return (f"{self.calls} paid call{'s' if self.calls != 1 else ''}, ${self.spent:.3f} this run; "
                f"ledger total ${self.before + self.spent:.3f}")


# ----- Calls through the cache -----

def fetch(request, budget, inputs=None, store="png", say=print, label=""):
    """The cached images for a request, or new ones: paid for within the budget, kept, logged. Returns (entry, new).

    request: the API body plus "endpoint" ("images/generations" or "images/edits"), "variant" (never sent) and, for
    an edit, "inputs" (the input images' sha256, in order; inputs holds their PNG bytes)."""
    hit = lookup(request)
    if hit is not None:
        return hit, False
    key = key_of(request)
    guess = estimate(request)
    budget.reserve(guess, label or request["model"])
    body = {k: v for k, v in request.items() if k not in ("endpoint", "variant", "inputs")}
    dropped = []
    started = time.monotonic()
    try:
        while True:
            try:
                if request["endpoint"] == "images/generations":
                    r = api.generate(body, say=say)
                else:
                    r = api.edit(body, inputs, say=say)
                break
            except api.ApiError as e:
                # A model that won't take input_fidelity (gpt-image-2 always works at high fidelity): once without.
                if e.status == 400 and "input_fidelity" in body and "input_fidelity" in e.message:
                    body.pop("input_fidelity")
                    dropped.append("input_fidelity")
                    continue
                raise
    except BaseException:
        budget.settle(guess, 0.0, paid=False)
        raise
    elapsed = round(time.monotonic() - started, 1)
    usage = r.get("usage")
    spent = cost(request["model"], usage)
    budget.settle(guess, spent if spent is not None else guess)
    images = [base64.b64decode(d["b64_json"]) for d in r.get("data", []) if d.get("b64_json")]
    if not images:
        raise api.ApiError(200, "the response had no image in it")
    d = folder(key)
    write_json(d / "request.json", request)
    for i, data in enumerate(images):
        if store == "webp":
            with Image.open(io.BytesIO(data)) as im:
                buf = io.BytesIO()
                im.save(buf, "WEBP", quality=90, method=6)
            write_bytes(d / f"{i}.webp", buf.getvalue())
        else:
            write_bytes(d / f"{i}.png", data)
    meta = {"made": now(), "model": request["model"], "endpoint": request["endpoint"], "elapsed_s": elapsed,
            "usage": usage, "cost_usd": spent if spent is not None else guess, "cost_estimated": spent is None,
            "stored_as": store, "images": len(images)}
    revised = [x.get("revised_prompt") for x in r.get("data", []) if x.get("revised_prompt")]
    if revised:
        meta["revised_prompt"] = revised[0] if len(revised) == 1 else revised
    for field in ("size", "quality", "background", "output_format"):
        if r.get(field) is not None:
            meta[f"returned_{field}"] = r[field]
    if dropped:
        meta["sent_without"] = dropped
    write_json(d / "meta.json", meta)
    _log({"at": meta["made"], "key": key, "label": label, "model": request["model"], "endpoint": request["endpoint"],
          "quality": request.get("quality"), "size": request.get("size"), "n": request.get("n", 1),
          "usage": usage, "cost_usd": meta["cost_usd"], "estimate_usd": guess, "elapsed_s": elapsed})
    return Entry(key), True


def store_local(request, image, store="png"):
    """Keeps an image made here, not bought (a layer cut out by make_art.py itself), under its request's key, so it's
    found the same way as a paid one. Costs nothing and adds no ledger line."""
    key = key_of(request)
    d = folder(key)
    buf = io.BytesIO()
    if store == "webp":
        image.save(buf, "WEBP", quality=90, method=6)
    else:
        image.save(buf, "PNG", compress_level=9)
    write_json(d / "request.json", request)
    write_bytes(d / f"0.{store}", buf.getvalue())
    write_json(d / "meta.json", {"made": now(), "model": "local", "endpoint": request["endpoint"], "cost_usd": 0.0,
                                 "stored_as": store, "images": 1})
    return Entry(key)


# ----- The concept index -----

def index():
    return read_json(INDEX, {"about": "Concepts by id: the cached image each one is (key, image), its kind, motif and "
                                      "model, its parent when it's a refinement, and its emblem layer once cut out.",
                             "concepts": {}})


def save_index(data):
    write_json(INDEX, data)


def add_concept(kind, key, image, info):
    """The id of a cached image as a concept (icon-01, feature-03, ...): its existing id, or the next free one."""
    with _lock:
        data = index()
        for cid, c in data["concepts"].items():
            if c["key"] == key and c.get("image", 0) == image:
                return cid
        numbers = [int(cid.split("-")[-1]) for cid, c in data["concepts"].items() if c["kind"] == kind]
        cid = f"{kind}-{(max(numbers) + 1 if numbers else 1):02d}"
        data["concepts"][cid] = dict(kind=kind, key=key, image=image, **info)
        save_index(data)
        return cid


def concept(cid):
    c = index()["concepts"].get(cid)
    if c is None:
        raise SystemExit(f"no concept {cid} (make_art.py sheet lists them)")
    return c


def update_concept(cid, **fields):
    with _lock:
        data = index()
        data["concepts"][cid].update(fields)
        save_index(data)


def concepts(kind):
    return {cid: c for cid, c in sorted(index()["concepts"].items()) if c["kind"] == kind}
