"""Prints the usage-data reports: the views in web/analytics/views.sql, over the events table on Railway.

The database is DATABASE_PUBLIC_URL (else DATABASE_URL) from the environment: `railway run --service Postgres` sets
it, or copy it from the Postgres service's Variables tab. It's never printed: it holds the password. With psycopg (or
psycopg2) installed, this makes the views again (they hold no data) and prints each report as a table. Without either,
or without a URL, it prints the SQL instead, to paste into the Postgres service's Data tab (Query) on Railway.

Usage (from the repo root):
  railway run --service Postgres py -3.13 tools/analytics_report.py               # every report
  railway run --service Postgres py -3.13 tools/analytics_report.py funnel shop   # some of them
  py -3.13 tools/analytics_report.py --sql                                        # just the SQL
  py -3.13 -m pip install "psycopg[binary]"                                       # once, to see the reports here
"""
import argparse
import datetime
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ROOT / "web" / "analytics" / "views.sql"

# name: (view, what it shows, a limit on its rows or None)
REPORTS = {
    "events": ("report_events", "What's arriving: each event, how many, from how many installs", None),
    "funnel": ("report_funnel", "How far players get: installs that did each step", None),
    "games": ("report_games", "Each game: players, chapters, ends, errors, and how answers were given", None),
    "ends": ("report_chapter_ends", "The ends players reach in each game, by node", None),
    "dropoff": ("report_drop_off", "Where players leave each game, most often first", 40),
    "shop": ("report_shop", "The shop by where it was opened from, and the purchases after", None),
    "retention": ("report_retention", "Day 1 and day 7 retention by the day an install was first seen", 30),
    "devices": ("report_devices", "What the apps run on: installs by app and kind of device", None),
}


def select(name):
    view, _, limit = REPORTS[name]
    return f"select * from {view}" + (f" limit {limit}" if limit else "") + ";"


def print_sql(names):
    print("-- 1. Make the views (run once, and again after views.sql changes):\n")
    print(VIEWS.read_text(encoding="utf-8"))
    print("-- 2. The reports:\n")
    for name in names:
        print(f"-- {REPORTS[name][1]}")
        print(select(name) + "\n")


def driver():
    """psycopg (3), or psycopg2, or None."""
    for module in ("psycopg", "psycopg2"):
        try:
            return __import__(module)
        except ImportError:
            pass
    return None


def cell(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, datetime.datetime):
        return value.astimezone(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M")
    return str(value)  # numbers (Decimal too) and dates as they are


def is_number(text):
    try:
        float(text)
        return True
    except ValueError:
        return False


def table(columns, rows):
    """The rows as a plain text table, numbers to the right."""
    cells = [[cell(v) for v in row] for row in rows]
    if not cells:
        return "  ".join(columns) + "\n(nothing yet)"
    widths = [max([len(c)] + [len(r[i]) for r in cells]) for i, c in enumerate(columns)]
    numeric = [all(r[i] == "" or is_number(r[i]) for r in cells) for i in range(len(columns))]

    def line(values):
        return "  ".join(v.rjust(w) if n else v.ljust(w) for v, w, n in zip(values, widths, numeric)).rstrip()

    return "\n".join([line(columns), "  ".join("-" * w for w in widths)] + [line(r) for r in cells])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("reports", nargs="*", help=f"which reports (default: all): {', '.join(REPORTS)}")
    ap.add_argument("--sql", action="store_true", help="print the SQL to paste into Railway's query tab, and stop")
    args = ap.parse_args()
    unknown = [r for r in args.reports if r not in REPORTS]
    if unknown:
        ap.error(f"no report called {', '.join(unknown)}; there are {', '.join(REPORTS)}")
    names = args.reports or list(REPORTS)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    url = os.environ.get("DATABASE_PUBLIC_URL") or os.environ.get("DATABASE_URL")
    db = driver()
    if args.sql or not url or not db:
        if not args.sql:
            why = "no DATABASE_PUBLIC_URL or DATABASE_URL" if not url else "no psycopg or psycopg2 installed"
            print(f"-- ({why}: here is the SQL to paste into the Postgres service's Data tab on Railway)\n")
        print_sql(names)
        return

    try:
        conn = db.connect(url, connect_timeout=15)
    except Exception as e:  # the message names the host, never the password
        sys.exit(f"Couldn't connect to the database: {str(e).strip().splitlines()[0].replace(url, '<url>')}")
    try:
        with conn.cursor() as cur:
            cur.execute(VIEWS.read_text(encoding="utf-8"))
        conn.commit()
        for name in names:
            with conn.cursor() as cur:
                cur.execute(select(name))
                columns = [d[0] for d in cur.description]
                rows = cur.fetchall()
            print(f"\n## {REPORTS[name][1]} ({REPORTS[name][0]})\n")
            print(table(columns, rows))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
