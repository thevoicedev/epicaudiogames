"""Checks the paid packs on the pack server against games/catalog.json, read-only, the way both apps fetch them.

For each pack in the catalog, <server>/<id>-<version>.zip (the R2 bucket, https://packs.epicaudiogames.com, in
docs/R2_PACKS.md) has to answer 200 with the catalog's size, and 206 to a range request: iOS carries on a broken-off
download from where it stopped. --sha downloads each zip (about 174 MB in all) and compares its SHA-256 with the
catalog's, since both apps refuse any other bytes. It also shows the pack server each app's release build gets from
its settings, which has to be the R2 one.

Errors (the exit code is 1 if there are any): a pack missing or the wrong size, no range support, a checksum that
differs, a release build pointed somewhere else. Nothing is uploaded or changed.

Usage (from the repo root): py -3.13 tools/check_packs.py [--sha] [--server URL]
"""
import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from check_store import CATALOG, R2_PACKS_URL, pack_urls

# A plain name for the server's logs. Python's own ("Python-urllib/3.13") is one that bot filters turn away.
USER_AGENT = "EpicAudioGames-check_packs/1 (+https://epicaudiogames.com)"
TIMEOUT = 60


def request(url, method="GET", headers=None):
    """The response to one request (any status), or the exception if the server couldn't be reached."""
    req = urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT, **(headers or {})})
    try:
        return urllib.request.urlopen(req, timeout=TIMEOUT)
    except urllib.error.HTTPError as e:      # a 4xx or 5xx is still an answer
        return e


def check_pack(server, pack, sha):
    """Errors and warnings for one pack, and a one-line summary."""
    errors, warnings = [], []
    name = f"{pack['id']}-{pack['version']}.zip"
    url = f"{server}/{name}"
    size = pack["size"]
    try:
        head = request(url, "HEAD")
        length = head.headers.get("Content-Length")
        if head.status != 200:
            return f"{name}: {head.status}", [f"{url} answers {head.status}, not 200"], warnings
        if length is None or int(length) != size:
            errors.append(f"{url} is {length} bytes; the catalog says {size}")
        cache = head.headers.get("Cache-Control")
        if not cache:
            warnings.append(f"{name} has no Cache-Control (the zips never change: \"public, max-age=31536000, "
                            f"immutable\" lets Cloudflare keep them)")

        part = request(url, headers={"Range": "bytes=0-99"})
        body = part.read()
        content_range = part.headers.get("Content-Range", "")
        if part.status != 206:
            errors.append(f"{url} answers {part.status} to a range request, not 206: a broken-off download starts "
                          f"again from the beginning")
        elif content_range != f"bytes 0-99/{size}" or len(body) != 100:
            errors.append(f"{url}: the range came back as {content_range!r} with {len(body)} bytes")

        summary = f"{name}: 200, {size / 1e6:.1f} MB, range {part.status}"
        if sha:
            started = time.monotonic()
            digest = hashlib.sha256()
            with request(url) as response:
                while chunk := response.read(1 << 20):
                    digest.update(chunk)
            seconds = time.monotonic() - started
            if digest.hexdigest() != pack["sha256"]:
                errors.append(f"{url}: SHA-256 {digest.hexdigest()}, the catalog says {pack['sha256']}")
            summary += f", SHA-256 {'matches' if digest.hexdigest() == pack['sha256'] else 'DIFFERS'}" \
                       f" ({size / 1e6 / max(seconds, 0.001):.1f} MB/s)"
        return summary, errors, warnings
    except (urllib.error.URLError, OSError, ValueError) as e:
        return f"{name}: no answer", [f"{url}: {e}"], warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--sha", action="store_true", help="download every zip and compare its SHA-256 with the catalog")
    ap.add_argument("--server", default=R2_PACKS_URL, help=f"the pack server (default {R2_PACKS_URL})")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    server = args.server.rstrip("/")

    failed = False
    print("Release builds' pack server:")
    for app, url, where in pack_urls():
        ok = url == R2_PACKS_URL
        print(f"  {'-' if ok else 'x'} {app}: {url or '(none)'} ({where}){'' if ok else ', not ' + R2_PACKS_URL}")
        failed = failed or not ok

    catalog = json.loads(Path(CATALOG).read_text(encoding="utf-8"))
    packs = [pack for game in catalog["games"] for pack in game.get("packs", [])]
    print(f"{server}: {len(packs)} packs in games/catalog.json")
    for pack in packs:
        summary, errors, warnings = check_pack(server, pack, args.sha)
        print(f"  {summary}")
        for message in errors:
            print(f"    x {message}")
        for message in warnings:
            print(f"    ! {message}")
        failed = failed or bool(errors)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
