"""Checks every game map (and its audio) against docs/MAP_FORMAT.md.

Errors (the exit code is 1 if there are any):
  - a node without exactly one of ask / go / end, or a go, redirect, answer or end pointing at a missing node;
  - a condition that doesn't parse or names an unknown variable, or a set of an unknown variable;
  - an answer with no way to match (or two), an unknown symbol table, a regular expression that doesn't compile
    or has a control character in it, an "opposite" pointing nowhere;
  - a clip without a transcript, or a transcript line outside its clip or with an unknown speaker;
  - a node the start can't reach, or one from which no end can be reached (the player would be stuck);
  - a missing audio file, or one whose length differs from the map's "dur".

Usage (from the repo root): python tools/validate.py [--game id] [--no-audio]
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "content"
EXTS = (".m4a", ".opus", ".mp3")
MATCHERS = ("yes", "no", "words", "repeat", "seq", "digits", "re", "any")
END_KINDS = ("ending", "chapter", "gameover")
APP_COMMANDS = {"stop", "cancel"}      # the app pauses on these (Commands.kt): never a map's answer

TOKEN = re.compile(r'"[^"]*"|\d+(?:\.\d+)?|[A-Za-z_]\w*|&&|\|\||==|!=|<=|>=|[-+*/%<>!?:(),]|\s+')
FUNCTIONS = {"max", "min", "floor"}
ENDS_BADLY = {"+", "-", "*", "/", "%", "<", ">", "!", "?", ":", "(", ",", "&&", "||", "==", "!=", "<=", ">="}


def condition_vars(expr):
    """The variables an expression (Expr.kt) uses; raises ValueError if it can't be read."""
    tokens = [t for t in TOKEN.findall(expr) if not t.isspace()]
    if "".join(tokens) != re.sub(r"\s+", "", expr):
        raise ValueError(f"can't read {expr!r}")
    depth = 0
    for t in tokens:
        depth += t == "("
        depth -= t == ")"
        if depth < 0:
            raise ValueError(f"unbalanced brackets in {expr!r}")
    if depth or not tokens or tokens[-1] in ENDS_BADLY:
        raise ValueError(f"can't read {expr!r}")
    for a, b in zip(tokens, tokens[1:]):
        if a in {"<", ">"} and b in {"<", ">"}:
            raise ValueError(f"can't read {expr!r}")
    names = []
    for i, t in enumerate(tokens):
        if re.fullmatch(r"[A-Za-z_]\w*", t) and t not in ("true", "false"):
            if t in FUNCTIONS and i + 1 < len(tokens) and tokens[i + 1] == "(":
                continue
            names.append(t)
    return names


class Checker:
    def __init__(self, game_map):
        self.m = game_map
        self.nodes = game_map["nodes"]
        self.vars = game_map.get("vars", {})
        self.errors, self.warnings = [], []

    def err(self, where, msg):
        self.errors.append(f"{where}: {msg}")

    def target(self, where, go):
        """Checks a go target; returns the node ids it can lead to."""
        if isinstance(go, str):
            if go not in self.nodes:
                self.err(where, f"goes to a missing node {go!r}")
            return [go]
        if not isinstance(go, dict) or len(go) == 0:
            self.err(where, f"bad go {go!r}")
            return []
        if "random" in go:
            return [t for x in go["random"] for t in self.target(where, x)]
        if "if" in go:
            out = []
            for case in go["if"]:
                self.cond(where, case.get("when"))
                out += self.target(where, case.get("go"))
            if "else" not in go:
                self.err(where, "an if without an else")
            else:
                out += self.target(where, go["else"])
            return out
        if "restart" in go:
            return self.target(where, go["restart"])
        if "draw" in go:
            if not go.get("deck"):
                self.err(where, "a draw without a deck")
            if not go["draw"]:
                self.err(where, "a draw from no nodes")
            return [t for x in go["draw"] for t in self.target(where, x)]
        if go.get("end") in ("quit", "leave"):
            return []
        self.err(where, f"bad go {go!r}")
        return []

    def cond(self, where, cond):
        if not isinstance(cond, str):
            self.err(where, f"bad condition {cond!r}")
            return
        try:
            for name in condition_vars(cond):
                if name not in self.vars:
                    self.err(where, f"condition {cond!r} uses an unknown variable {name!r}")
        except ValueError as e:
            self.err(where, str(e))

    def sets(self, where, values):
        for name, value in (values or {}).items():
            if name not in self.vars:
                self.err(where, f"sets an unknown variable {name!r}")
            if isinstance(value, str) and re.match(r"^[+-]\d", value) and not isinstance(self.vars.get(name), (int, float)):
                self.err(where, f"adds to {name!r}, which isn't a number")
            if isinstance(value, str) and value.startswith("="):
                self.cond(where, value[1:])

    def steps(self, where, steps):
        for i, s in enumerate(steps or []):
            here = f"{where} step {i + 1}"
            if "when" in s:
                self.cond(here, s["when"])
            if "play" in s:
                if not isinstance(s.get("dur"), (int, float)) or s["dur"] <= 0:
                    self.err(here, "a clip without a length")
                lines = s.get("lines") or []
                if not lines and not s.get("sfx"):
                    self.err(here, f"{s['play']} has no transcript (music and sound effects are marked sfx)")
                for ln in lines:
                    if ln.get("who") not in self.m.get("who", {}):
                        self.err(here, f"unknown speaker {ln.get('who')!r}")
                    if not ln.get("text"):
                        self.err(here, "an empty transcript line")
                    if ln.get("at", -1) < 0 or ln["at"] + ln.get("len", 0) > s.get("dur", 0) + 0.05:
                        self.err(here, f"line at {ln.get('at')} s doesn't fit in the {s.get('dur')} s clip")
            elif "num" in s:
                if not isinstance(self.vars.get(s["num"]), (int, float)):
                    self.err(here, f"reads out {s['num']!r}, which isn't a number variable")
            elif "bed" in s:
                if s["bed"] is not None and not (0 <= s.get("volume", 1) <= 1):
                    self.err(here, f"a bed's volume {s.get('volume')!r} isn't between 0 and 1")
            elif "pick" in s:
                if not s["pick"]:
                    self.err(here, "a pick from nothing")
                for k, option in enumerate(s["pick"]):
                    self.steps(f"{here} pick {k + 1}", option)
            elif "by" in s:
                if s["by"] not in self.vars:
                    self.err(here, f"by an unknown variable {s['by']!r}")
                for k, option in (s.get("cases") or {}).items():
                    self.steps(f"{here} case {k}", option)
                self.steps(f"{here} else", s.get("else"))
            elif "pause" not in s:
                self.err(here, f"unknown step {s!r}")

    def answers(self, where, ask):
        answers = ask.get("answers") or []
        out = []
        for i, a in enumerate(answers):
            here = f"{where} answer {i + 1}"
            kinds = [k for k in ("seq", "digits", "re", "repeat", "any") if a.get(k) not in (None, False)]
            if a.get("yes") or a.get("no"):
                kinds.append("yes" if a.get("yes") else "no")
            elif a.get("words") is not None:
                kinds.append("words")
            if len(kinds) != 1:
                self.err(here, f"needs exactly one way to match, has {kinds or 'none'}")
            if "seq" in a:
                table = self.m.get("symbols", {}).get(a.get("symbols"))
                if table is None:
                    self.err(here, f"unknown symbol table {a.get('symbols')!r}")
                elif any(ch not in table for ch in a["seq"]) or (not a["seq"] and "least" not in a):
                    self.err(here, f"sequence {a['seq']!r} has symbols not in {a.get('symbols')!r}")
            if "digits" in a and not re.fullmatch(r"\d+" if "least" not in a else r"\d*", str(a["digits"])):
                self.err(here, f"digits {a['digits']!r} aren't digits")
            if "re" in a:
                try:
                    re.compile(a["re"])
                except re.error as e:
                    self.err(here, f"bad regular expression: {e}")
                if re.search(r"[\x00-\x1f\x7f]", a["re"]):
                    # Spoken text never has one: most likely a "\b" that lost its backslash.
                    self.err(here, f"a control character in the regular expression {a['re']!r}")
            if "words" in a and not all(isinstance(w, str) and w.strip("=").strip() for w in a["words"]):
                self.err(here, "an empty phrase")
            for w in a.get("words", []):
                if isinstance(w, str) and w.lstrip("=") in APP_COMMANDS:
                    self.warnings.append(f"{here}: \"{w}\" pauses the app, so it never reaches this answer")
            if "when" in a:
                self.cond(here, a["when"])
            if "rank" in a and not isinstance(a["rank"], int):
                self.err(here, f"rank {a['rank']!r} isn't a whole number")
            self.sets(here, a.get("set"))
            if "opposite" in a and not (isinstance(a["opposite"], int) and 0 <= a["opposite"] < len(answers)
                                        and a["opposite"] != i):
                self.err(here, f"opposite {a['opposite']!r} isn't another answer")
            if "go" in a:
                out += self.target(here, a["go"])
        if not answers:
            self.err(where, "a question with no answers")
        e = ask.get("else")
        if isinstance(e, dict):
            self.steps(f"{where} else", e.get("say"))
            self.sets(f"{where} else", e.get("set"))
            if "go" in e:
                out += self.target(f"{where} else", e["go"])
        elif e is not None:
            out += self.target(f"{where} else", e)
        if not ask.get("reprompt"):
            self.warnings.append(f"{where}: no reprompt")
        self.steps(f"{where} reprompt", ask.get("reprompt"))
        for b in ask.get("buttons") or []:
            if not b.get("label") or not b.get("value"):
                self.err(where, f"a button needs a label and a value: {b!r}")
        if len(ask.get("buttons") or []) > 4:
            self.warnings.append(f"{where}: more than four buttons")
        return out

    def run(self):
        m = self.m
        if m.get("format") != 1:
            self.err("map", f"format {m.get('format')!r}, expected 1")
        if m.get("start") not in self.nodes:
            self.err("map", f"start {m.get('start')!r} isn't a node")
        if m.get("repeat", "reprompt") not in ("say", "reprompt"):
            self.err("map", f"repeat {m.get('repeat')!r} isn't say or reprompt")
        mixed = m.get("words", {}).get("mixed")
        if mixed is not None and not (isinstance(mixed, dict) and all(isinstance(mixed.get(k, []), list) for k in ("yes", "no", "filler"))):
            self.err("map", "words.mixed needs yes, no and filler lists")
        for name in m.get("keep", []):
            if name not in self.vars:
                self.err("map", f"keeps an unknown variable {name!r}")
        edges, ends = {}, set()
        for nid, n in self.nodes.items():
            where = f"node {nid}"
            nexts = []
            for r in n.get("redirect", []):
                self.cond(where, r.get("when"))
                nexts += self.target(where, r.get("go"))
            self.sets(where, n.get("set"))
            self.steps(where, n.get("say"))
            finish = [k for k in ("ask", "go", "end") if k in n]
            if len(finish) != 1:
                self.err(where, f"needs exactly one of ask, go and end; has {finish or 'none'}")
            if "ask" in n:
                nexts += self.answers(where, n["ask"])
            if "go" in n:
                nexts += self.target(where, n["go"])
            if _quits(n):
                ends.add(nid)
            if "end" in n:
                end = n["end"]
                ends.add(nid)
                if end.get("kind") not in END_KINDS:
                    self.err(where, f"end kind {end.get('kind')!r}")
                if not end.get("title"):
                    self.err(where, "an end without a title")
                if end.get("next") and not end.get("locked"):
                    nexts += self.target(where, end["next"])
                if end.get("kind") == "chapter" and not end.get("next"):
                    self.err(where, "a chapter end without a next chapter")
                if end.get("retry"):
                    nexts += self.target(where, end["retry"])
            edges[nid] = [t for t in nexts if t in self.nodes]
        # Reachability, from the start and back from the ends.
        seen, todo = set(), [m.get("start")]
        while todo:
            nid = todo.pop()
            if nid in seen or nid not in edges:
                continue
            seen.add(nid)
            todo += edges[nid]
        lost = sorted(set(self.nodes) - seen)
        if lost:
            self.err("map", f"{len(lost)} nodes can't be reached from the start: {', '.join(lost[:12])}"
                            f"{', ...' if len(lost) > 12 else ''}")
        back = {nid: [] for nid in self.nodes}
        for nid, outs in edges.items():
            for t in outs:
                back[t].append(nid)
        alive, todo = set(), list(ends)
        while todo:
            nid = todo.pop()
            if nid in alive:
                continue
            alive.add(nid)
            todo += back[nid]
        stuck = sorted(seen - alive)
        if stuck:
            self.err("map", f"no end can be reached from {len(stuck)} nodes (the player would be stuck): "
                            f"{', '.join(stuck[:12])}{', ...' if len(stuck) > 12 else ''}")
        return self


def _quits(node):
    """Whether any answer, else or go of this node leaves the game."""
    def quits(go):
        if isinstance(go, dict):
            if go.get("end") in ("quit", "leave"):
                return True
            return any(quits(c.get("go")) for c in go.get("if", [])) or quits(go.get("else"))
        return False
    ask = node.get("ask") or {}
    pieces = [node.get("go")] + [a.get("go") for a in ask.get("answers", [])]
    e = ask.get("else")
    pieces.append(e.get("go") if isinstance(e, dict) else e)
    return any(quits(p) for p in pieces)


def plays(game_map):
    """Every clip and bed the map plays, with its length, inside picks and cases too."""
    out = {}

    def walk(steps):
        for s in steps or []:
            if "play" in s:
                out[s["play"]] = s["dur"]
            elif s.get("bed"):
                out[s["bed"]] = s.get("dur", 0)
            elif "pick" in s:
                for option in s["pick"]:
                    walk(option)
            elif "by" in s:
                for option in (s.get("cases") or {}).values():
                    walk(option)
                walk(s.get("else"))

    for node in game_map["nodes"].values():
        walk(node.get("say"))
        ask = node.get("ask")
        if ask:
            walk(ask.get("reprompt"))
            if isinstance(ask.get("else"), dict):
                walk(ask["else"].get("say"))
    return out


def audio_problems(game, clips):
    def check(item):
        path, dur = item
        files = [CONTENT / game / f"{path}{e}" for e in EXTS if (CONTENT / game / f"{path}{e}").exists()]
        if not files:
            return f"{path}: no audio file", 0
        p = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
                            str(files[0])], capture_output=True, text=True)
        try:
            got = float(p.stdout.strip())
        except ValueError:
            return f"{path}: can't read {files[0].name}", files[0].stat().st_size
        if dur and abs(got - dur) > 0.12:
            return f"{path}: the map says {dur:.2f} s, {files[0].name} is {got:.2f} s", files[0].stat().st_size
        return None, files[0].stat().st_size
    problems, size = [], 0
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for problem, nbytes in pool.map(check, clips.items()):
            size += nbytes
            if problem:
                problems.append(problem)
    return sorted(problems), size


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game")
    ap.add_argument("--no-audio", action="store_true", help="skip the audio files")
    args = ap.parse_args()
    failed = False
    for path in sorted((ROOT / "games").glob("*/map.json")):
        game = path.parent.name
        if args.game and game != args.game:
            continue
        game_map = json.loads(path.read_text(encoding="utf-8"))
        c = Checker(game_map).run()
        if game_map.get("id") != game:
            c.err("map", f"id {game_map.get('id')!r} doesn't match its folder {game!r}")
        clips = plays(game_map)
        secs = sum(clips.values())
        summary = f"{game}: {len(game_map['nodes'])} nodes, {len(clips)} clips, {secs / 60:.1f} min"
        if not args.no_audio:
            problems, size = audio_problems(game, clips)
            c.errors += problems
            summary += f", {size / 1e6:.1f} MB of audio"
        print(f"{summary}: {'OK' if not c.errors else f'{len(c.errors)} errors'}")
        for e in c.errors:
            print(f"  x {e}")
        for w in c.warnings:
            print(f"  ! {w}")
        failed = failed or bool(c.errors)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
