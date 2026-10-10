"""Store art for Epic Audio Games: the app icon, the Play feature graphic, the website's icons and social image, and
the framed store screenshots, from AI concept art (OpenAI's image models) to the exact files each app, store and
page wants. docs/STORE_ART.md is the guide; brand/ holds the brand's settings, prompts and the owner's picks.

Every image paid for is kept in tools/cache/art/ (committed), and what it cost in tools/cache/art/ledger.jsonl, so
nothing is paid for twice; a budget guard stops a run before it spends more than --budget (and brand.json's overall
limit). The OpenAI key is OPENAI_API_KEY, from the environment or all-minigames-sites/alexa/.env; it is never printed.
Everything after the concepts (layers --method local, sheet, export, shots, check) works offline and costs nothing.

Usage (from the repo root):
  py -3.13 tools/make_art.py models                  the key's image models, what the probe found, which get used
  py -3.13 tools/make_art.py probe [--model M]       a transparent 1024 image and a 1536x752 one from each model
  py -3.13 tools/make_art.py concepts icon --n 8 --quality medium --budget 5     one concept per motif
  py -3.13 tools/make_art.py refine icon icon-03 --n 4 --note "thicker band"
  py -3.13 tools/make_art.py layers icon icon-03     the emblem on a transparent background
  py -3.13 tools/make_art.py sheet icon              build/art/review/icon.html and .png (approval gate 3)
  py -3.13 tools/make_art.py pick icon icon-03       the owner's choice -> brand/picks.json, brand/masters/
  py -3.13 tools/make_art.py export all              every icon and store/web image, into the apps, stores, website
  py -3.13 tools/make_art.py export all --icon icon-03 --out build/art/test-export      a trial, apps untouched
  py -3.13 tools/make_art.py shots android           frame build/store-shots/android/raw/*.png for Play
  py -3.13 tools/make_art.py check [--out DIR]
"""
import argparse
import sys


def ids(text):
    return [int(x) for x in text.split(",") if x.strip()] if text else None


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawTextHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)

    sub.add_parser("models", help="the image models the key can use, and which ones the tool would pick")

    p = sub.add_parser("probe", help="try each preferred model: a transparent background and a custom size")
    p.add_argument("--model", action="append", help="probe only this model (repeatable)")
    p.add_argument("--budget", type=float, help="most this run may spend, in US dollars")
    p.add_argument("--force", action="store_true", help="probe again (new images) even when cached")

    p = sub.add_parser("concepts", help="concept art from brand/prompts/<kind>.json")
    p.add_argument("kind", choices=["icon", "feature"])
    p.add_argument("--n", type=int, default=8, help="how many (one per motif in turn; default 8)")
    p.add_argument("--model", help="this model instead of brand.json's preference")
    p.add_argument("--quality", default="medium", help="low, medium, high (xhigh, max on 2.5 models); default medium")
    p.add_argument("--motifs", type=ids, help="only these motif ids, e.g. 1,3")
    p.add_argument("--budget", type=float, help="most this run may spend, in US dollars (default brand.json's)")
    p.add_argument("--workers", type=int, default=2, help="requests at once (default 2)")
    p.add_argument("--dry-run", action="store_true", help="show the requests and their likely cost, ask for nothing")
    p.add_argument("--force", action="store_true", help="new takes even where a concept is cached")

    p = sub.add_parser("refine", help="new takes on one concept (an edit of its image)")
    p.add_argument("kind", choices=["icon", "feature"])
    p.add_argument("id")
    p.add_argument("--n", type=int, default=4)
    p.add_argument("--note", help="what to change, in words")
    p.add_argument("--model")
    p.add_argument("--quality")
    p.add_argument("--budget", type=float)
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("layers", help="an icon concept's emblem on a transparent background")
    p.add_argument("kind", choices=["icon"])
    p.add_argument("id")
    p.add_argument("--method", choices=["auto", "local", "edit", "keyed"], default="auto",
                   help="auto: cut out here if the background allows, else an edit with a transparent background, "
                        "else an edit on flat magenta keyed out here")
    p.add_argument("--model", help="the model for the edits")
    p.add_argument("--budget", type=float)
    p.add_argument("--force", action="store_true", help="cut it again (and pay again for an edit)")

    p = sub.add_parser("sheet", help="the review sheet: build/art/review/<kind>.html and .png")
    p.add_argument("kind", choices=["icon", "feature", "shots"])
    p.add_argument("--ids", help="only these concepts, e.g. icon-01,icon-04")
    p.add_argument("--out", help="the framed screenshots to show (sheet shots; default the store folders)")

    p = sub.add_parser("pick", help="the owner's choice: brand/picks.json and brand/masters/")
    p.add_argument("kind", choices=["icon", "feature"])
    p.add_argument("id")
    p.add_argument("--budget", type=float, help="for the layer, if it has to be made")

    p = sub.add_parser("export", help="every file cut from the picked art (deterministic, offline)")
    p.add_argument("what", choices=["icons", "store", "web", "all"])
    p.add_argument("--out", help="write under this folder instead of the repo (a trial: the apps are untouched)")
    p.add_argument("--icon", help="use this icon concept instead of the pick (needs its layer)")
    p.add_argument("--feature", help="use this feature concept instead of the pick")
    p.add_argument("--check", action="store_true", help="write nothing; fail if any file differs from a fresh export")

    p = sub.add_parser("shots", help="frame raw store screenshots with their captions")
    p.add_argument("platform", choices=["android", "ios"])
    p.add_argument("--raw", help="the raw captures (default brand/shots.json's)")
    p.add_argument("--claims", default="", help="claims the device test has earned, e.g. voiceover,talkback")
    p.add_argument("--sizes", default="6.9,6.3", help="iOS display sizes (default 6.9,6.3)")
    p.add_argument("--out", help="write under this folder instead of the store folders")
    p.add_argument("--replace", action="store_true", help="remove the folder's other screenshots (the old set)")

    p = sub.add_parser("check", help="check the brand files, the cache and every exported image")
    p.add_argument("--out", help="check a trial export under this folder instead of the repo")

    args = ap.parse_args()
    try:
        run(args)
    except KeyboardInterrupt:
        sys.exit("stopped")


def run(args):
    from art import api
    try:
        if args.command == "models":
            from art.concepts import run_models
            run_models()
        elif args.command == "probe":
            from art.concepts import run_probe
            run_probe(args.model, args.budget, args.force)
        elif args.command == "concepts":
            from art.concepts import run_concepts
            run_concepts(args.kind, args.n, args.model, args.quality, args.motifs, args.budget, args.workers,
                         args.dry_run, args.force)
        elif args.command == "refine":
            from art.concepts import run_refine
            run_refine(args.id, args.n, args.note, args.model, args.quality, args.budget, args.workers, args.dry_run,
                       args.force)
        elif args.command == "layers":
            from art.layers import run_layers
            run_layers(args.id, args.method, args.model, args.budget, args.force)
        elif args.command == "sheet":
            from art.sheet import run_sheet
            run_sheet(args.kind, args.ids.split(",") if args.ids else None, args.out)
        elif args.command == "pick":
            from art.icons import run_pick
            run_pick(args.kind, args.id, args.budget)
        elif args.command == "export":
            from art.icons import run_export
            sys.exit(run_export(args.what, args.out, args.icon, args.feature, args.check))
        elif args.command == "shots":
            from art.shots import run_shots
            run_shots(args.platform, args.raw, [c for c in args.claims.split(",") if c], args.sizes.split(","),
                      args.out, args.replace)
        elif args.command == "check":
            from art.check import run_check
            sys.exit(run_check(args.out))
    except api.ApiError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
