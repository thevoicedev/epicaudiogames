"""Builds games/<id>/map.json for the three radio plays from the Mini Games sources.

Inputs, all read-only:
  tools/flows/<game>.json    each game's flow and word lists, read out of the skill code by extract_flows.js
  alexa/tools/<game>/        in all-minigames-sites: script.json and the mixer, which give every line's text,
                             speaker and start time (tools/rp_timings.py, cached in tools/cache/timings/)

The maps follow docs/MAP_FORMAT.md and copy the Alexa versions' behaviour: the same branches, the same answer
words, the same reprompts and "sorry" clips. What the app does differently (no coins, no upsell, no other games
to switch to) is left out: endings stop at the end of the story, where the app shows its own end screen.

Usage (from the repo root): python tools/build_maps.py [--cached]
  --cached   reuse tools/cache/timings/*.json instead of laying the games out again
The whole of Frootopia (stories 1 to 5), for its pack (tools/make_pack.py):
  python tools/build_maps.py --cached --frootopia-stories 5 --build build/packs
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MINI = Path(os.environ.get("MINIGAMES_DIR") or ROOT.parent / "all-minigames-sites")
RADIOPLAY = MINI / "alexa" / "tools" / "radioplay"
FLOWS = ROOT / "tools" / "flows"
TIMINGS = ROOT / "tools" / "cache" / "timings"
GAMES = ROOT / "games"

# The answer words for "repeat" where the skill used Alexa's built-in repeat intent (Frootopia's own list).
REPEAT_WORDS = ["repeat", "repeat that", "say that again", "say it again", "what did you say", "come again", "pardon",
                "one more time"]
YES_NO = [{"label": "Yes", "value": "yes"}, {"label": "No", "value": "no"}]
from skill import words as skill_words  # noqa: E402  (the skill-wide yes/no rules)
# Answer ranks (higher first): Frootopia and Signal Decoders check a node's own words and "not sure" first, then
# "no", then "yes", so "yeah no" is a no.
RANK_FIRST, RANK_NO = 2, 1

# Speaker names for the transcript, where the voice key alone doesn't say it.
NAMES = {"PIPRULER": "Pip", "ROT": "Admiral Rot", "KITCHEN": "Narrator", "DOGLADY": "Dog Lady", "VOICE": "The Voice"}

NUMBER_WORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9}


class Game:
    """One game's sources: its flow (from the skill) and its audio timings (from the mixer)."""

    def __init__(self, flow_name, tools_name, cached):
        self.flow = json.loads((FLOWS / f"{flow_name}.json").read_text(encoding="utf-8"))
        self.timings = timings(tools_name, cached)
        self.warnings = []

    def step(self, kind, slug):
        """A "play" step: a clip of the game's audio and its transcript lines."""
        clip = self.timings[kind].get(slug)
        if clip is None:
            raise KeyError(f"no {kind} clip {slug!r} in the mixer's layout")
        return {"play": f"{kind}/{slug}", "dur": clip["dur"],
                "lines": [{"at": ln["at"], "len": ln["len"], "who": ln["who"], "text": ln["text"]} for ln in clip["lines"]]}

    def prompt(self, slug):
        """The voiced reprompt for a question, if the game has one."""
        if slug in self.timings["prompts"]:
            return [self.step("prompts", slug)]
        self.warnings.append(f"{slug}: no reprompt clip")
        return []


def timings(tools_name, cached):
    out = TIMINGS / f"{tools_name}.json"
    if not (cached and out.exists()):
        env = dict(os.environ, RP_GAME_DIR=str(MINI / "alexa" / "tools" / tools_name))
        subprocess.run([sys.executable, str(ROOT / "tools" / "rp_timings.py"), str(RADIOPLAY), str(out)], env=env, check=True)
    return json.loads(out.read_text(encoding="utf-8"))


def pick(targets):
    """A list of next nodes: one of them at random (the skill's getRandomElement)."""
    return targets[0] if len(targets) == 1 else {"random": list(targets)}


def who_names(nodes):
    keys = {ln["who"] for n in nodes.values() for steps in steps_of(n) for s in steps for ln in s.get("lines", [])}
    return {k: NAMES.get(k, k.title()) for k in sorted(keys)}


def steps_of(node):
    yield node.get("say", [])
    ask = node.get("ask")
    if ask:
        yield ask.get("reprompt", [])
        if isinstance(ask.get("else"), dict):
            yield ask["else"].get("say", [])


def reachable(nodes, start):
    """Every node id reachable from start."""
    seen, todo = set(), [start]
    while todo:
        nid = todo.pop()
        if nid in seen or nid not in nodes:
            continue
        seen.add(nid)
        todo += list(targets_of(nodes[nid]))
    return seen


def targets_of(node):
    def of(go):
        if isinstance(go, str):
            yield go
        elif isinstance(go, dict):
            for t in go.get("random", []):
                yield t
            for case in go.get("if", []):
                yield from of(case["go"])
            if "else" in go:
                yield from of(go["else"])
            if "restart" in go:
                yield go["restart"]
    for r in node.get("redirect", []):
        yield from of(r["go"])
    yield from of(node.get("go"))
    ask = node.get("ask")
    if ask:
        for a in ask["answers"]:
            yield from of(a.get("go"))
        e = ask.get("else")
        yield from of(e.get("go") if isinstance(e, dict) else e)
    end = node.get("end")
    if end and end.get("next") and not end.get("locked"):
        yield end["next"]


# ----- Noodle Rush -----

def noodle_rush(cached):
    g = Game("noodle-rush", "noodle-rush", cached)
    f = g.flow
    nodes = {}
    for n in f["flow"]:
        nid, slug = n["id"], n["slug"]
        node = {}
        if n.get("redirect"):
            node["redirect"] = [{"when": n["redirect"]["flag"], "go": n["redirect"]["to"]}]
        if n.get("setFlag"):
            node["set"] = {n["setFlag"]: True}
        node["say"] = [g.step("scenes", slug)]
        if n["type"] == "ending":
            node["end"] = {"kind": "ending", "title": n["description"].split(" - ")[-1]}
            nodes[nid] = node
            continue
        choices = n["choices"]
        forward = [k for k in choices if k not in ("yes", "no")]
        answers = []
        # doNoodleYes: a node without a "yes" takes its one forward option, if it has exactly one.
        yes = choices.get("yes") or (choices[forward[0]] if len(forward) == 1 else None)
        if yes:
            answers.append({"yes": True, "go": pick(yes)})
        # doNoodleNo: "no" on the title leaves; on a one-option question it gives up.
        if choices.get("no"):
            answers.append({"no": True, "go": pick(choices["no"])})
        elif nid == "Page1":
            answers.append({"no": True, "go": "_no-problem"})
        elif len(forward) == 1:
            answers.append({"no": True, "go": "_give-up"})
        for key in forward:
            answers.append({"words": f["choiceWords"][key], "go": pick(choices[key])})
        # repromptNoodle: anything else plays the question again.
        node["ask"] = {"reprompt": g.prompt(slug), "answers": answers, "buttons": YES_NO}
        nodes[nid] = node
    nodes["_no-problem"] = {"say": [g.step("common", "no-problem")], "go": {"end": "quit"}}
    nodes["_give-up"] = {"say": [g.step("common", "give-up")], "go": {"end": "quit"}}
    return g, {
        "id": "noodle-rush", "title": "Noodle Rush", "start": "Page1",
        # The skill has no repeat intent: "repeat" is an answer it doesn't know, which plays the question again.
        "vars": {"nana": False}, "repeat": "reprompt",
        # doNoodleAnswer only takes a yes or a no that is the whole answer ("I'm not sure" isn't a yes).
        "words": {"yes": [f"={x}" for x in f["words"]["yes"]], "no": [f"={x}" for x in f["words"]["no"]], "repeat": REPEAT_WORDS},
        "nodes": nodes,
    }


# ----- The Kingdom of Frootopia (story 1 free; 2 to 5 in the pack) -----

FROOTOPIA_PACK = "frootopia-stories"
RECAP = "fr{}-0"            # "Previously...", played before stories 2 to 5 (the skill's RECAPS)


def frootopia(cached, stories=1):
    g = Game("frootopia", "frootopia", cached)
    f = g.flow
    by_id = {n["id"]: n for n in f["flow"]}
    start = f["stories"]["1"]
    w = f["words"]
    named = f["namedAnswerIs"]
    choice_words = f["nodeChoiceWords"]
    unhandled = {"say": [g.step("common", "unhandled")]}       # repromptFrootopia
    nodes = {}

    def build(nid):
        n = by_id[nid]
        kind = n["type"]
        say = [g.step("scenes", nid)]
        if kind == "pass":
            # Stats (hope, morale, fuel) never change the story; the app doesn't keep them.
            return {"say": say, "go": n["next"]}
        if kind == "exit":
            return {"say": say, "go": {"end": "quit"}}
        if kind == "story":                     # stories 2 to 5 (FR_FLOWS' storyNode)
            kind = {"passthrough": "pass", "scene": "scene", "ending": "ending"}[n["kind"]]
            if kind == "pass":
                return {"say": say, "go": n["next"]}
        if kind == "ending":
            # finishStory: story 1's ending is followed by its sting (Gribbo's pocket starts to glow), a teaser for
            # story 2. Each story's end leads to the next one's recap; those after the free stories are locked.
            story = n["story"]
            if story == 1:
                say = say + [g.step("scenes", "fr-sting")]
            title = n.get("description") or f"Story {story} complete!"
            if story == 5:
                return {"say": say, "end": {"kind": "ending", "title": "The End"}}
            end = {"kind": "chapter", "title": title, "next": RECAP.format(story + 1)}
            if story >= stories:
                end["locked"] = FROOTOPIA_PACK
            return {"say": say, "end": end}
        if kind not in ("scene", "gameover"):
            raise ValueError(f"{nid}: unexpected node type {kind!r}")
        yes, no = (("_restart", "fr-exit") if kind == "gameover" else (n.get("yes"), n.get("no")))
        # doFrootopiaAnswer: the node's own words first (fr-9: "fight" or "run"), then "no", then "yes".
        answers = []
        for side, target in (("yes", yes), ("no", no)):
            if choice_words.get(nid, {}).get(side):
                answers.append({"words": choice_words[nid][side], "go": target, "rank": RANK_FIRST})
        if yes:
            answers.append({"yes": True, "go": yes})
        if no:
            answers.append({"no": True, "go": no, "rank": RANK_NO})
        if not (yes and no):
            g.warnings.append(f"{nid}: has no {'yes' if not yes else 'no'} branch")
        # NAMED_ANSWER_IS: kids answer fr-12 with the part they need ("a pipe"); any answer counts.
        if named.get(nid):
            answers.append({"any": True, "go": yes if named[nid] == "yes" else no})
        return {"say": say, "ask": {"reprompt": g.prompt(nid), "answers": answers, "else": unhandled, "buttons": YES_NO}}

    todo = [start]
    while todo:
        nid = todo.pop()
        if nid in nodes or nid.startswith("_"):
            continue
        nodes[nid] = build(nid)
        todo += [t for t in targets_of(nodes[nid]) if t not in nodes]
        end = nodes[nid].get("end")
        if end and end.get("next") and "locked" not in end:
            todo.append(end["next"])
    # startStory(replay): "Let's start the adventure again, from the very beginning!"
    nodes["_restart"] = {"say": [g.step("common", "restart")], "go": {"restart": start}}
    left_out = sorted(i for i in by_id if i.split("-")[0] in [f"fr{k}" if k > 1 else "fr" for k in range(1, stories + 1)]
                      and i not in nodes and i != "fr-sting")
    if left_out:
        g.warnings.append(f"story 1 nodes that can't be reached, left out: {', '.join(left_out)}")
    return g, {
        "id": "frootopia", "title": "The Kingdom of Frootopia", "start": start,
        "vars": {}, "repeat": "say",
        "words": {"yes": w["yes"] + [f"={x}" for x in w["yesExact"]], "no": w["no"], "repeat": w["repeat"]},
        "nodes": nodes,
    }


# ----- Signal Decoders (Alien Invasion) -----

# Each puzzle's check function in the skill, as answers. "tries >= 1": the looser answers count after a hint.
LETTERS_CAC = [{"seq": "cac", "symbols": "letters", "spelled": True},
               {"re": r"\b(cac|kak|cack|kack|cak|kac|caac|cacc|kaka?k)\b"}]
PUZZLE_ANSWERS = {
    "isCAC": LETTERS_CAC,
    "is42211": [{"digits": "42211"}, {"digits": "2211", "exact": True, "when": "tries >= 1"}],
    "isLRRL": [{"seq": "lrrl", "symbols": "turns"}, {"seq": "rrl", "symbols": "turns", "exact": True, "when": "tries >= 1"}],
    "is314": [{"digits": "314"}, {"digits": "14", "exact": True, "when": "tries >= 1"}],
    "isSOS": [{"re": r"\b(sos|s o s|esos|s0s|essoess)\b"}, {"seq": "sos", "symbols": "sos"}],
    "is11224": [{"digits": "11224"}, {"digits": "1224", "exact": True, "when": "tries >= 1"},
                {"digits": "224", "exact": True, "when": "tries >= 1"}],
    "isHHL": [{"seq": "hhl", "symbols": "notes"}, {"seq": "l", "symbols": "notes", "exact": True, "when": "tries >= 1"}],
    "isTen": [{"digits": "10"}],
}
# answerPuzzle counts anything that looks like an answer (p1OrP2Answer: two or more letters, digits, turns or notes,
# or an SOS) as a try, even with "again" in it; only other answers with a repeat word play the question again.
LOOKS_LIKE_AN_ANSWER = [
    {"seq": "", "symbols": "letters", "spelled": True, "least": 2},
    {"re": r"(cac|kak|cack|kack|cak|kac|caac|cacc|kaka?k)"},
    {"digits": "", "least": 2},
    {"seq": "", "symbols": "turns", "least": 2},
    {"seq": "", "symbols": "notes", "least": 2},
    {"re": r"(sos|s o s|esos|s0s|essoess)"},
    {"seq": "sos", "symbols": "sos"},
]
CHOICE_FN = re.compile(r'aiState\(ad\)\.(\w+) === "(\w+)" \? "([\w-]+)" : "([\w-]+)"')


def signal_decoders(cached):
    g = Game("signal-decoders", "alien-invasion", cached)
    f = g.flow
    w = f["words"]
    chapters = {int(k): v for k, v in f["chapters"].items()}
    puzzles = f["puzzles"]
    titles = chapter_titles(g, chapters)
    sorry = g.step("common", "unhandled")
    nodes = {}

    def go_of(nxt):
        if isinstance(nxt, str):
            return nxt
        m = CHOICE_FN.search(nxt["fn"])
        if not m:
            raise ValueError(f"can't read the next node from {nxt['fn']!r}")
        var, value, then, other = m.groups()
        return {"if": [{"when": f'{var} == "{value}"', "go": then}], "else": other}

    for n in f["flow"]:
        nid, kind = n["id"], n["type"]
        say = [g.step("scenes", nid)]
        if kind == "pass":
            node = {"say": say, "go": go_of(n["next"])}
            if nid.endswith("-reveal") or nid.endswith("-yes"):
                node = {"set": {"tries": 0}, **node}
        elif kind == "exit":
            node = {"say": say, "go": {"end": "quit"}}
        elif kind == "ending":
            ch = n["chapter"]
            end = {"kind": "chapter", "title": titles[ch], "next": chapters[ch + 1]} if ch + 1 in chapters \
                else {"kind": "ending", "title": titles[ch]}
            node = {"say": say, "end": end}
        elif kind == "question":
            # doAlienInvasionAnswer: "not sure" asks again (it has a "sure" in it), then "no" ("no thanks", "don't"),
            # then "yes".
            node = {"say": say, "ask": {
                "reprompt": g.prompt(nid),
                "answers": [{"words": w["unsure"], "rank": RANK_FIRST}, {"no": True, "go": n["no"], "rank": RANK_NO},
                            {"yes": True, "go": n["yes"]}],
                "else": {"say": [sorry] + g.prompt(nid)},
                "buttons": YES_NO}}
        elif kind == "puzzle":
            p = puzzles[n["puzzle"]]
            answers = [dict(a, go=p["correct"]) for a in PUZZLE_ANSWERS[p["check"]]]
            answers += [dict(a) for a in LOOKS_LIKE_AN_ANSWER]        # no go: a wrong try (the else)
            answers.append({"repeat": True, "go": p["again"]})
            node = {"say": say, "ask": {
                "reprompt": g.prompt(nid),
                "answers": answers,
                # answerPuzzle: every other answer is a wrong try; the second one reveals the answer.
                "else": {"set": {"tries": "+1"}, "go": {"if": [{"when": "tries >= 2", "go": p["reveal"]}], "else": p["hint"]}},
                "buttons": p["options"]}}
            if nid == p["start"]:
                node = {"set": {"tries": 0}, **node}
        elif kind == "choice":
            # answerChoice: "repeat" first; then follow or hide ("don't follow" is a hide, "let's not hide" a
            # follow); both, or neither, asks again.
            node = {"say": say, "ask": {
                "reprompt": g.prompt(nid),
                "answers": [
                    {"words": w["follow"], "set": {"choice": "follow", "episode1Choice": "follow"}, "go": "ai-end", "opposite": 1},
                    {"words": w["hide"], "set": {"choice": "hide", "episode1Choice": "hide"}, "go": "ai-end", "opposite": 0},
                    {"repeat": True, "go": nid, "rank": 1},
                ],
                "else": {"say": [sorry] + g.prompt(nid)},
                "buttons": [{"label": "Follow", "value": "follow"}, {"label": "Hide", "value": "hide"}]}}
        else:
            raise ValueError(f"{nid}: unexpected node type {kind!r}")
        nodes[nid] = node
    return g, {
        "id": "signal-decoders", "title": "Signal Decoders", "start": chapters[1],
        "vars": {"tries": 0, "choice": "", "episode1Choice": ""}, "repeat": "say",
        "words": {"yes": w["yes"], "no": w["no"], "repeat": w["repeat"]},
        "symbols": f["symbols"],
        "nodes": nodes,
    }


def chapter_titles(g, chapters):
    """"Chapter 2: The Map in the Music", from each chapter's title scene ("Chapter two. The Map in the Music.")."""
    titles = {}
    for ch, nid in chapters.items():
        text = " ".join(ln["text"] for ln in g.timings["scenes"][nid]["lines"])
        m = re.search(r"Chapter (\w+)[.,:]\s*(.+?)[.!]", text)
        if m and NUMBER_WORDS.get(m.group(1).lower()) == ch:
            titles[ch] = f"Chapter {ch}: {m.group(2).strip()}"
        else:
            titles[ch] = f"Chapter {ch}"
            g.warnings.append(f"{nid}: no chapter title in {text[:80]!r}")
    return titles


def write_map(g, data, build=None):
    nodes = data["nodes"]
    lost = sorted(set(nodes) - reachable(nodes, data["start"]))
    if lost:
        g.warnings.append(f"unreachable nodes: {', '.join(lost)}")
    words = skill_words(data["words"]["yes"], data["words"]["no"], data["words"]["repeat"])
    out = {"format": 1, "id": data["id"], "title": data["title"], "start": data["start"], "vars": data["vars"],
           "repeat": data["repeat"], "who": who_names(nodes), "words": words}
    if data.get("symbols"):
        out["symbols"] = data["symbols"]
    out["nodes"] = nodes
    path = (Path(build) / data["id"] if build else GAMES / data["id"]) / "map.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    asks = sum(1 for n in nodes.values() if "ask" in n)
    ends = sum(1 for n in nodes.values() if "end" in n)
    clips = {s["play"] for n in nodes.values() for steps in steps_of(n) for s in steps if "play" in s}
    secs = sum(g.timings[c.split("/")[0]][c.split("/", 1)[1]]["dur"] for c in clips)
    print(f"{data['id']}: {len(nodes)} nodes ({asks} questions, {ends} ends), {len(clips)} clips, "
          f"{secs / 60:.1f} min of audio -> {path}")
    for warning in g.warnings:
        print(f"  ! {warning}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--cached", action="store_true", help="reuse the cached timings")
    ap.add_argument("--frootopia-stories", type=int, default=1, help="Frootopia stories to build (all of them: 5)")
    ap.add_argument("--build", help="a folder for a pack build: only Frootopia, written to <build>/frootopia/")
    args = ap.parse_args()
    if args.build:
        write_map(*frootopia(args.cached, args.frootopia_stories), build=args.build)
        return
    for build in (noodle_rush, frootopia, signal_decoders):
        write_map(*build(args.cached))


if __name__ == "__main__":
    main()
