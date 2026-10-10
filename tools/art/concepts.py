"""Concept art: what the key's image models can do (models, probe), icon and feature-graphic ideas from
brand/prompts/<kind>.json (concepts), and new takes on one concept (refine).

Every request goes through cache.fetch, so a concept already made costs nothing; each new one gets the next id
(icon-01, icon-02, ...) in tools/cache/art/index.json. Concepts are kept as WebP at quality 90 (they're only looked
at); the files the apps get are cut later from a transparent PNG layer (layers.py).
"""
import io
from concurrent.futures import ThreadPoolExecutor

from . import api
from .brand import CACHE, brand, now, prompts, read_json, write_json
from .cache import Budget, BudgetExceeded, Entry, add_concept, concept, estimate, fetch, lookup, pixels_hash

PROBE = CACHE / "probe.json"
PROBE_TRANSPARENT = ("A simple flat icon: a solid golden (#FFD54F) circle with a thick white ring around it, centred, "
                     "with nothing else in the image.")
PROBE_WIDE = "A simple wide banner: plain deep navy blue with one thick golden wave across the middle. No text."
_listed = None


def listed():
    """The image models the key can use (asked once per run)."""
    global _listed
    if _listed is None:
        _listed = api.image_models()
    return _listed


def probes():
    return read_json(PROBE, {"about": "What each image model did when make_art.py probe tried it: a transparent "
                                      "background (alpha), a custom size (1536x752).", "models": {}})


def choose_model(requested=None, transparent=False, custom_size=False):
    """The model to use: the one asked for, else the first of brand.json's preferences the key can use that the probe
    hasn't seen fail (and, when needed, that the probe saw make a transparent background or a custom size)."""
    if requested:
        return requested
    seen = probes()["models"]
    available = listed()
    for m in brand()["models"]["prefer"]:
        p = seen.get(m, {})
        if m not in available or p.get("generate") is False:
            continue
        if transparent and p.get("transparent") is not True:
            continue
        if custom_size and p.get("customSize") is not True:
            continue
        return m
    if transparent and "gpt-image-1" in available and seen.get("gpt-image-1", {}).get("transparent") is not False:
        return "gpt-image-1"            # documented to make transparent PNGs, even if not probed yet
    if custom_size:
        return None
    raise SystemExit("None of brand.json's preferred image models is available to this key (make_art.py models).")


def uses_fidelity(model):
    """Whether a model takes input_fidelity (gpt-image-2 and later always work at high fidelity, and refuse it)."""
    return not model.startswith("gpt-image-2")


def png_bytes(image):
    buf = io.BytesIO()
    image.save(buf, "PNG")
    return buf.getvalue()


# ----- models and probe -----

def run_models():
    ids = listed()
    seen = probes()["models"]
    prefer = brand()["models"]["prefer"]
    print("Image models this key can use:")
    for m in ids:
        notes = []
        if m in prefer:
            notes.append(f"preference {prefer.index(m) + 1}")
        p = seen.get(m)
        if p:
            notes.append("transparent: " + {True: "yes", False: "no", None: "?"}[p.get("transparent")])
            notes.append("custom size: " + {True: "yes", False: "no", None: "?"}[p.get("customSize")])
        print(f"  {m:34} {', '.join(notes)}")
    missing = [m for m in prefer if m not in ids]
    if missing:
        print("Preferred but not available: " + ", ".join(missing))
    print(f"Concepts would use: {choose_model()}")
    t = choose_model(transparent=True)
    print(f"Transparent layers would use: {t or 'none confirmed (run probe)'}")
    if not seen:
        print("Nothing probed yet: make_art.py probe tries each preferred model (two low-quality images each).")


def _alpha_report(image):
    """What a probe image's alpha says: the share of fully transparent pixels and whether the corners are clear."""
    if image.mode != "RGBA":
        return {"alpha": False, "clear": 0.0, "corners": False}
    a = image.getchannel("A")
    w, h = image.size
    hist = a.histogram()
    clear = hist[0] / (w * h)
    corners = all(a.getpixel(p) == 0 for p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)])
    return {"alpha": True, "clear": round(clear, 3), "corners": corners}


def run_probe(models=None, budget_limit=None, force=False):
    budget = Budget(budget_limit)
    data = probes()
    todo = models or [m for m in brand()["models"]["prefer"] if m in listed()]
    for m in todo:
        before = data["models"].get(m, {})
        result = {"listed": m in listed(), "checked": now()}
        print(f"{m}:")
        ok = asked = False
        words = {"transparent": "transparent", "customSize": "custom size"}
        tries = [("transparent", {"endpoint": "images/generations", "model": m, "prompt": PROBE_TRANSPARENT,
                                  "size": "1024x1024", "quality": "low", "background": "transparent",
                                  "output_format": "png", "n": 1, "variant": 0}),
                 ("customSize", {"endpoint": "images/generations", "model": m, "prompt": PROBE_WIDE,
                                 "size": "1536x752", "quality": "low", "background": "opaque",
                                 "output_format": "png", "n": 1, "variant": 0})]
        for name, req in tries:
            if force:
                while lookup(req) is not None:
                    req["variant"] += 1
            elif before.get(name) is False and str(before.get(name + "Note", "")).startswith("400"):
                # The model refused it outright last time (a 400 isn't cached, as nothing was made): not asked again.
                result[name], result[name + "Note"] = False, before[name + "Note"]
                print(f"  {words[name]}: no ({before[name + 'Note'][:160]}; recorded, --force asks again)")
                continue
            try:
                # Kept as WebP: only looked at, and its alpha (what the probe is about) stays lossless.
                entry, new = fetch(req, budget, store="webp", label=f"probe {name} {m}")
            except BudgetExceeded as e:
                print(f"  stopped: {e}")
                write_json(PROBE, data)
                print(budget.summary())
                return
            except api.ApiError as e:
                if e.status in (401, 403):
                    raise SystemExit(str(e))
                asked = True
                result[name] = False
                result[name + "Note"] = f"{e.status}: {e.message}"[:300]
                print(f"  {words[name]}: no ({e.status}: {e.message[:160]})")
                continue
            ok = True
            asked = asked or new
            image = entry.image()
            how = "new" if new else "cached"
            result.setdefault("keys", {})[name] = entry.key
            if name == "transparent":
                rep = _alpha_report(image)
                result["transparent"] = bool(rep["alpha"] and rep["clear"] >= 0.2 and rep["corners"])
                result["transparentNote"] = (f"{image.mode} {image.size[0]}x{image.size[1]}, {rep['clear']:.0%} fully "
                                             f"transparent, corners {'clear' if rep['corners'] else 'not clear'}")
                print(f"  transparent: {'yes' if result['transparent'] else 'no'} ({result['transparentNote']}; "
                      f"{how}, ${entry.meta['cost_usd']:.4f})")
            else:
                result["customSize"] = image.size == (1536, 752)
                result["customSizeNote"] = f"asked 1536x752, got {image.size[0]}x{image.size[1]}"
                print(f"  custom size: {'yes' if result['customSize'] else 'no'} ({result['customSizeNote']}; "
                      f"{how}, ${entry.meta['cost_usd']:.4f})")
        result["generate"] = ok
        if not asked and before.get("checked"):
            result["checked"] = before["checked"]       # nothing new was asked: the last real check stands
        data["models"][m] = result
        write_json(PROBE, data)
    print(budget.summary())


# ----- concepts and refinements -----

def concept_request(kind, motif, model, quality, variant):
    p = prompts(kind)
    size = p["size"]
    if size not in ("1024x1024", "1536x1024", "1024x1536", "auto") and not probes()["models"].get(model, {}).get(
            "customSize"):
        size = p.get("fallbackSize", "1536x1024")
    return {"endpoint": "images/generations", "model": model, "prompt": p["base"].replace("{motif}", motif["prompt"]),
            "size": size, "quality": quality, "background": p.get("background", "opaque"), "output_format": "png",
            "n": 1, "variant": variant}


def _run(kind, jobs, budget, workers, dry_run):
    """Runs jobs ({label, request, inputs, info}) through the cache, two at a time by default, and indexes each new
    image as a concept. Stops scheduling at the first budget stop or key error; other failures skip that job."""
    if dry_run:
        total = 0.0
        for job in jobs:
            req = job["request"]
            hit = lookup(req)
            guess = 0.0 if hit else estimate(req)
            total += guess
            print(f"  {job['label']}: {req['model']} {req['quality']} {req['size']} "
                  f"{'cached' if hit else f'about ${guess:.3f}'}")
        print(f"Would cost about ${total:.3f} (dry run: nothing was asked for).")
        return []
    stop = []

    def one(job):
        if stop:
            return None
        try:
            entry, new = fetch(job["request"], budget, inputs=job.get("inputs"), store="webp",
                               label=f"{kind} {job['label']}")
        except BudgetExceeded as e:
            stop.append(str(e))
            return None
        except api.ApiError as e:
            if e.status in (401, 403):
                stop.append(str(e))
            print(f"  {job['label']}: failed: {e}")
            return None
        if new:
            print(f"  {job['label']}: made (${entry.meta['cost_usd']:.4f}, {entry.meta['elapsed_s']} s)")
        return entry, new

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        results = list(pool.map(one, jobs))
    # Ids in the order of the jobs (motif order), whatever order the requests finished in.
    made = []
    for job, result in zip(jobs, results):
        if result:
            entry, new = result
            cid = add_concept(kind, entry.key, 0, dict(job["info"], made=entry.meta["made"]))
            made.append(cid)
            print(f"  {cid}: {job['label']} ({'new' if new else 'cached'}, ${entry.meta['cost_usd']:.4f})")
    if stop:
        print(f"Stopped: {stop[0]}")
    print(budget.summary())
    return made


def run_concepts(kind, n, model=None, quality="medium", motifs=None, budget_limit=None, workers=2, dry_run=False,
                 force=False):
    """n concepts, one per motif in turn (a second round of the motifs makes second takes)."""
    p = prompts(kind)
    chosen = [m for m in p["motifs"] if not motifs or m["id"] in motifs]
    if not chosen:
        raise SystemExit(f"no motif {motifs} in brand/prompts/{kind}.json")
    model = choose_model(model)
    jobs, used = [], {}
    for i in range(n):
        motif = chosen[i % len(chosen)]
        req = concept_request(kind, motif, model, quality, i // len(chosen))
        if force:
            while lookup(req) is not None or req["variant"] in used.get(motif["id"], ()):
                req["variant"] += 1
        used.setdefault(motif["id"], set()).add(req["variant"])
        label = f"motif {motif['id']} {motif['name']}" + (f", take {req['variant'] + 1}" if req["variant"] else "")
        jobs.append({"label": label, "request": req,
                     "info": {"motif": motif["id"], "motifName": motif["name"], "model": model, "quality": quality,
                              "size": req["size"], "take": req["variant"]}})
    budget = Budget(budget_limit)
    print(f"{n} {kind} concept{'s' if n != 1 else ''} with {model} at {quality} quality "
          f"(budget ${budget.limit:.2f}):")
    return _run(kind, jobs, budget, workers, dry_run)


def run_refine(cid, n=4, note=None, model=None, quality=None, budget_limit=None, workers=2, dry_run=False,
               force=False):
    """n new takes on a concept: an edit of its image that keeps the idea and makes it bolder and simpler (plus the
    note, if one's given)."""
    c = concept(cid)
    kind = c["kind"]
    p = prompts(kind)
    model = choose_model(model)
    quality = quality or c.get("quality", "medium")
    image = Entry(c["key"]).image(c.get("image", 0)).convert("RGB")
    data = png_bytes(image)
    motif = next((m for m in p["motifs"] if m["id"] == c.get("motif")), None)
    prompt = p["refine"] + (f" {motif['prompt']}" if motif else "") + (f" {note.strip()}" if note else "")
    jobs = []
    for i in range(n):
        req = {"endpoint": "images/edits", "model": model, "prompt": prompt, "size": c.get("size", p["size"]),
               "quality": quality, "background": "opaque", "output_format": "png", "n": 1,
               "inputs": [pixels_hash(image)], "variant": i}
        if uses_fidelity(model):
            req["input_fidelity"] = "high"
        if force:
            while lookup(req) is not None:
                req["variant"] += n
        jobs.append({"label": f"{cid} refined, take {i + 1}", "request": req, "inputs": [data],
                     "info": {"motif": c.get("motif"), "motifName": c.get("motifName"), "model": model,
                              "quality": quality, "size": req["size"], "take": req["variant"], "parent": cid,
                              "note": note}})
    budget = Budget(budget_limit)
    print(f"{n} refinement{'s' if n != 1 else ''} of {cid} with {model} at {quality} quality:")
    return _run(kind, jobs, budget, workers, dry_run)
