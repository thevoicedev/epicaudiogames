"""Builds games/pirate-quest/map.json: Pirate Quest, the whole gamebook (89 nodes in the skill).

Each node is one of the skill's PIRATE_GAME_FLOW nodes (alexa/lambda/Games/pirate-quest/index.js), as
tools/extract_games.js recorded it running: the crew's recorded scenes (speech-to-text gives a line per speaker
turn), Alexa's lines in Jessica's voice, the pauses, the stats it changes, and the choices it offers with the
skill's words for each (PIRATE_UTTERANCE_MAP; yes and no are Alexa's own).

Stats: coins and reputation change what is heard (the dice need 10 coins and say how many you have; the Spanish
trick works with a reputation of 30), so they are variables, changed once per node as the skill does
(processedNodes). Health, morale and the journal change nothing that is heard, and are left out. The royal
information (from ac-18, ac-25a or ac-25b) decides what ac-23 is.

Differences from the skill, on purpose:
- no Mini Games coins, play limit or upsell at Treasure Island: the whole quest is free;
- the dice are read highest first ("You rolled 5, 4, 2"), so 56 recorded throws cover them all; "You have N coins"
  is recorded for every amount up to 1,000;
- "no" to sailing on after the first fight (ac-exit) says "Thanks for playing." and leaves, keeping your place
  (Alexa ended the session there, and carried on from there next time); the Mini Games advert after it is left out;
- broke at the second dice game (ac-22b), you go on to the tavern (ac-23), not back to the first inn (ac-9);
- the shanty's "You can listen to this shanty at any point in minigames by saying: Shanty." is left out, and the
  game's end is the app's end screen (no "earned 100 coins", no "play again, or a different game?");
- "repeat" plays the node again: Alexa replayed its current node, which after ac-5a3, ac-12shanty and ac-18shanty
  was another node (and gave its coins again); the recruit choice doesn't take "repeat", as Alexa's own repeat
  took it first;
- the skill's welcome back on a new session is the app's own "Welcome back!".

Usage (from the repo root): python tools/games/piratequest.py   (after node tools/extract_games.js pirate-quest)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import Content, HOST  # noqa: E402
from skill import words  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GAME = "pirate-quest"
F = json.loads((ROOT / "tools" / "flows" / f"{GAME}.json").read_text(encoding="utf-8"))
FLOW = {n["id"]: n for n in F["nodes"]}
A, U = F["audio"], F["utterances"]
CREW = "CREW"                               # the recorded scenes: One-Eyed Will, the crew and everyone they meet
STATS = {"coins": (0, None), "reputation": (0, 100)}    # the stats kept, with the skill's limits
MAX_COINS = 1000

c = Content(GAME, "en/audio2/pirate-quest/")
YES_NO = [{"label": "Yes", "value": "yes"}, {"label": "No", "value": "no"}]


def say(text):
    return c.tts(text)


def rec(rel):
    """One of the skill's recordings: a scene with a line per speaker turn, or a sound."""
    return c.clip(rel.removeprefix("pirate-quest/"), who=CREW, turns=True)


def by(var, cases, otherwise=None, when=None):
    step = {"by": var, "cases": {str(k): v for k, v in cases.items()}}
    if otherwise is not None:
        step["else"] = otherwise
    if when:
        step["when"] = when
    return step


def steps(items):
    """A node's recording as map steps. Back-to-back lines are one clip, as the skill's speech joins them."""
    out, lines = [], []

    def flush():
        if lines:
            out.append(say(" ".join(lines)))
            lines.clear()

    for it in items:
        if "voice" in it:
            lines.append(it["voice"].strip())
        elif "audio" in it:
            flush()
            out.append(rec(it["audio"]))
        elif "silence" in it:
            flush()
            out.append({"pause": it["silence"] / 1000})
        elif "mixer" in it or "seq" in it:
            raise ValueError(f"a mixer in a node: {it}")
    flush()
    return out


def flag_var(node_id):
    return "d_" + node_id.replace("-", "_")


def stat_sets(node_id, items):
    """updatePirateStat: coins and reputation, once per node (processedNodes); the story flags it sets."""
    sets = {}
    once = [i for i in items if i.get("stat") in STATS and i.get("once")]
    flag = flag_var(node_id)
    for i in once:
        lo, hi = STATS[i["stat"]]
        new = f"max({lo}, {i['stat']} + {i['value']})"
        new = f"min({hi}, {new})" if hi is not None else new
        assert i["stat"] not in sets, f"{node_id} changes {i['stat']} twice"
        sets[i["stat"]] = f"={flag} ? {i['stat']} : {new}"
    if once:
        sets[flag] = True
    for i in items:
        if "flag" in i:
            sets[i["flag"]] = i["value"]
    return sets


def current(node_id, items):
    """The node whose choices apply after this one (the last setCurrentNode; the node itself if none)."""
    marks = [i["node"] for i in items if "node" in i]
    return marks[-1] if marks else node_id


LABELS = {"yes": "Yes", "no": "No"}


def ask(at, prompt_again):
    """The question of flow node `at`: its choices with the skill's words, its reprompt for anything else."""
    node = FLOW[at]
    answers, buttons = [], []
    for key, targets in node["options"].items():
        go = targets[0] if len(targets) == 1 else {"random": targets}
        if key in ("yes", "no"):
            answers.append({key: True, "go": go})
        else:
            said = sorted({w.lower() for w in U.get(key, [key])} - {"repeat"})
            answers.append({"words": said, "go": go})
        buttons.append({"label": LABELS.get(key, key.capitalize()), "value": key})
    opts = node["options"]
    if "duel" in opts and "no" not in opts:         # doPirateQuestNo: "no" is a mishear of "joe", i.e. duel
        answers.append({"no": True, "go": opts["duel"][0]})
    if "board" in opts:                             # doPiratePickNumber: 4 is board, 5 is fight
        answers.append({"digits": "4", "exact": True, "go": opts["board"][0]})
    if "fight" in opts:
        answers.append({"digits": "5", "exact": True, "go": opts["fight"][0]})
    else_text = (node["reprompt"] or "Try again, Captain!").strip()
    return {"reprompt": [say(prompt_again or else_text)], "answers": answers, "else": {"say": [say(else_text)]},
            "buttons": buttons[:4]}


def dice(node_id, opening, closing, then_when_broke, prompt):
    """getDiceOutcome and its lines: three dice each, read highest first, and the 10-coin wager."""
    roll = {}
    for who in ("p", "e"):
        for k in (1, 2, 3):
            roll[f"{who}{k}"] = "rand(1,6)"
    for who in ("p", "e"):
        d = f"{who}1, {who}2, {who}3"
        roll[f"{who}hi"] = f"=max({d})"
        roll[f"{who}lo"] = f"=min({d})"
        roll[f"{who}t"] = f"={who}1 + {who}2 + {who}3"
        roll[f"{who}k"] = f"={who}hi * 100 + ({who}t - {who}hi - {who}lo) * 10 + {who}lo"
    roll["coins0"] = "=coins"
    roll["coins"] = "=pt > et ? coins + 10 : (pt < et ? max(0, coins - 10) : coins)"
    throws = [(h, m, lo) for h in range(1, 7) for m in range(1, h + 1) for lo in range(1, m + 1)]

    def rolled(lead, end):
        return {f"{h}{m}{lo}": [say(f"{lead} {h}, {m}, {lo} for a total of {h + m + lo}{end}")] for h, m, lo in throws}

    def coins(var):
        return by(var, {n: [say(f"You have {n} coins. ")] for n in range(0, MAX_COINS + 1, 5)},
                  otherwise=[say(f"You have more than {MAX_COINS:,} coins. ")])

    spend = rec(f"pirate-quest/{A['spendCoin']}.mp3")
    node = {
        "redirect": [{"when": "coins < 10", "go": f"{node_id}-broke"}],
        "set": roll,
        "say": [*([coins("coins0")] if opening else []),
                say("You wager 10 coins. "), spend, say("And roll three dice. "),
                rec(f"pirate-quest/{A['rollDice']}.mp3"),
                by("pk", rolled("You rolled", "!")),
                say(opening and "Now its your opponents go. " or "Now it's your opponents go. "),
                rec(f"pirate-quest/{A['enemyRoll']}.mp3"),
                by("ek", rolled("They rolled", ".")),
                dict({"pick": [[rec(f"pirate-quest/{A['diceWin']}.mp3"),
                                {"pick": [[rec(f"pirate-quest/{w}.mp3")] for w in A["pirateWin"]]},
                                say("You won 10 coins. "), spend]]}, when="pt > et"),
                dict(rec(f"pirate-quest/{A['diceLose']}.mp3"), when="pt < et"),
                dict(rec(f"pirate-quest/{A['diceDraw']}.mp3"), when="pt == et"),
                coins("coins"), *closing],
        "ask": ask(node_id, prompt),
    }
    broke = {"say": [rec(f"pirate-quest/{A['pouchEmpty']}.mp3")], "go": then_when_broke}
    return node, broke


def reachable():
    """The flow nodes a player can get to from ac-1: by the choices, and by the nodes that go on to another in the
    same turn (ac-8b and ac-22b when broke, ac-23 without the royal information). The skill also has ac-26d and
    ac-26f, which nothing leads to."""
    seen, todo = set(), ["ac-1"]
    while todo:
        nid = todo.pop()
        if nid in seen:
            continue
        seen.add(nid)
        n = FLOW[nid]
        todo += [t for targets in n["options"].values() for t in targets]
        todo += [i["node"] for r in n["runs"] for i in r["items"] if "node" in i]
    return seen | {"ac-23"}


def build():
    nodes = {}
    # Launch (doPlayPirateQuest): the title, then the first node.
    nodes["begin"] = {"say": [rec(F["intro"])], "go": "ac-1"}

    live = reachable()
    for nid, n in FLOW.items():
        if nid not in live:
            continue
        runs = n["runs"]
        items = runs[0]["items"]
        if nid == "ac-diffGame":                    # "no" to starting: doDifferentGame
            nodes[nid] = {"say": [say("Begin your pirate adventure another time. ")], "go": {"end": "quit"}}
            continue
        if nid == "ac-exit":                        # ExitFlow.doExit, without its advert
            nodes[nid] = {"say": [say("Thanks for playing. ")], "go": {"end": "leave"}}
            continue
        if nid == "complete-game":                  # the end: the Mini Games coins and "play again" are the app's
            nodes[nid] = {"say": [rec(f"pirate-quest/{A['pqGameOver']}.mp3")],
                          "end": {"kind": "ending", "title": "You completed Pirate Quest!"}}
            continue
        if nid == "ac-8b":
            nodes[nid], nodes[f"{nid}-broke"] = dice(nid, True, [{"pause": 1.0}, say("Say roll, or leave. ")], "ac-9",
                                                     runs[0]["reprompt"])
            continue
        if nid == "ac-22b":
            nodes[nid], nodes[f"{nid}-broke"] = dice(nid, False, [say("Want to try again? ")], "ac-23",
                                                     runs[0]["reprompt"])
            continue
        if nid == "ac-shanty":                      # the shanty, without "say: Shanty" (a Mini Games command)
            items = [i for i in items if "listen to this shanty at any point" not in i.get("voice", "")]

        node = {}
        if nid == "ac-23":
            # Without the royal information, the crew meets Captain Blacktooth instead (ac-25).
            items = next(r for r in runs if r["stats"].get("royalInfo"))["items"]
            node["redirect"] = [{"when": "!royalInfo", "go": "ac-25"}]
        sets = stat_sets(nid, items)
        if sets:
            node["set"] = sets
        if nid == "ac-16c":
            # The trick works with a reputation of 30 or more: the steps where the two runs differ.
            good = next(r for r in runs if r["stats"].get("reputation", 0) >= 30)["items"]
            a, b = steps(items), steps(good)
            start = next(i for i in range(min(len(a), len(b))) if a[i] != b[i])
            end = next(i for i in range(1, min(len(a), len(b))) if a[-i] != b[-i]) - 1
            node["say"] = (a[:start] + [{"pick": [b[start:len(b) - end]], "when": "reputation >= 30"},
                                        {"pick": [a[start:len(a) - end]], "when": "reputation < 30"}]
                           + a[len(a) - end:])
        else:
            others = [r for r in runs[1:] if [i for i in r["items"] if "read" not in i]
                      != [i for i in items if "read" not in i]]
            if others and nid != "ac-23":
                raise ValueError(f"{nid}: its runs differ, and the builder doesn't say how")
            node["say"] = steps(items)
        node["ask"] = ask(current(nid, items), runs[0]["reprompt"] if nid != "ac-23" else
                          next(r for r in runs if r["stats"].get("royalInfo"))["reprompt"])
        nodes[nid] = node
    return nodes


nodes = c.prepare(build)

variables = {"coins": F["start"]["coins"], "reputation": F["start"]["reputation"], "royalInfo": False,
             "firedNavigator": False, "coins0": 0}
for who in ("p", "e"):
    variables.update({f"{who}{k}": 0 for k in (1, 2, 3)})
    variables.update({f"{who}{x}": 0 for x in ("hi", "lo", "t", "k")})
live = reachable()
for nid, n in FLOW.items():
    if nid in live and any(i.get("stat") in STATS and i.get("once") for r in n["runs"] for i in r["items"]):
        variables[flag_var(nid)] = False

game_map = {
    "format": 1,
    "id": GAME,
    "title": "Pirate Quest",
    "start": "begin",
    "vars": variables,
    "repeat": "say",
    "who": {HOST: "", CREW: ""},
    "words": words(["yes", "yeah", "yep", "yup", "sure"], ["no", "nope", "nah"],
                   ["repeat", "repeat that", "say that again", "say it again", "what did you say", "come again",
                    "pardon", "one more time"]),
    "nodes": nodes,
}
out = ROOT / "games" / GAME / "map.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(game_map, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
n_files, size = c.size_report()
print(f"{GAME}: {len(nodes)} nodes, {n_files} audio files, {size / 1e6:.1f} MB -> {out.relative_to(ROOT)}")
