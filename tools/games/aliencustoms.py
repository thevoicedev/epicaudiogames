"""Builds games/alien-customs/map.json: Alien Customs, levels 1 to 5 (the free ones; 6 to 15 come in a pack).

Each node mirrors one of the skill's headless responses (alexa/lambda/Games/alien-customs/index.js): the level intro,
each item's announcement (Slug's rules), the officer's questions with his recorded right and wrong replies, the
round results, the deportation and the win. A level's three items come in a random order (a deck), as the skill
shuffles them. The officer and Slug are recordings (transcribed); Alexa's lines are Jessica's.

Differences from the skill, on purpose:
- no coins, play limits or "play again, or a different game?": a won level is a chapter end whose next is the
  next level (the skill's replay picks the next level too), a deportation is a game over that retries the level;
- yes and no to the officer are forgiving ("yes it is" counts; "no" outranks "yes"), as Alexa's own Yes and No
  intents are; the skill's Answer intent wants the bare word;
- the swipe between Slug's first two rules is one fixed swipe per item (the skill picks one of six at random);
  the swipes elsewhere stay random.

Usage (from the repo root): python tools/games/aliencustoms.py   (after node tools/extract_games.js alien-customs)
The full game, for its pack (tools/make_pack.py): python tools/games/aliencustoms.py --levels 15 --build build/packs
"""
import argparse
import json
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import Content, HOST  # noqa: E402
from skill import NO, YES, words  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GAME = "alien-customs"
F = json.loads((ROOT / "tools" / "flows" / f"{GAME}.json").read_text(encoding="utf-8"))
A, ITEMS, SUFFIX, NAMES = F["audio"], F["items"], F["suffix"], F["names"]
PASS, FAIL, PER_ITEM = F["rules"]["pass"], F["rules"]["fail"], F["rules"]["questions"]
FREE = 5                                   # levels in the base game
ap = argparse.ArgumentParser()
ap.add_argument("--levels", type=int, default=FREE, help="levels to build (all of them: 15)")
ap.add_argument("--build", help="a folder for a pack build: the map and its audio go to <build>/alien-customs/")
ARGS = ap.parse_args()
LEVELS = F["levels"][:ARGS.levels]
DIALOGUE = A["dialogue"]
OUT = Path(ARGS.build) / GAME if ARGS.build else None

c = Content(GAME, F["cdn"], voices={"dialogue/": "OFFICER", "slug-audio/": "SLUG"},
            fixes={"allergy, Cloud": "allergy cloud", "Large umbrellas or diamond-catching": "Large umbrellas are diamond-catching"},
            out=OUT / "content" if OUT else None)
YES_NO = [{"label": "Yes", "value": "yes"}, {"label": "No", "value": "no"}]


def say(text):
    return c.tts(text)


def dialogue(key, text=None):
    """One of the officer's recorded lines (the skill's getAlienCustomsDialogue)."""
    return c.clip(DIALOGUE[key], text=text)


def slug(key):
    return c.clip(f"slug-audio/{key}.mp3")


def louder(step, volume, name):
    """A clip at another volume (the skill's changeVolume on it): pre-mixed with that gain."""
    return c.mix(name, [{"step": step, "volume": volume}])


def round_states(questions):
    """What can happen in a round (handleYesNo): the questions that can be asked, and for each question and
    answer ("r" right, "w" wrong) the results it can lead to: "pass", "lose" or "next" (the next question)."""
    asked, results, todo, seen = set(), {}, [(0, 0, 0)], set()
    while todo:
        i, ok, bad = todo.pop()
        if (i, ok, bad) in seen:
            continue
        seen.add((i, ok, bad))
        asked.add(i)
        for kind, ok2, bad2 in (("r", ok + 1, bad), ("w", ok, bad + 1)):
            if ok2 >= PASS:
                res = "pass"
            elif bad2 >= FAIL:
                res = "lose"
            elif i + 1 >= questions:
                res = "pass" if ok2 >= PASS else "lose"
            else:
                res = "next"
                todo.append((i + 1, ok2, bad2))
            results.setdefault((i, kind), set()).add(res)
    return asked, results


def outcome(possible, targets, next_key, i, questions):
    """The go after an answer, with a branch for each result that can happen (the counters already updated)."""
    cases = []
    if "pass" in possible and len(possible) > 1:
        cases.append({"when": f"ok >= {PASS}", "go": targets["pass"]})
    if "lose" in possible and len(possible) > 1 and "next" in possible:
        cases.append({"when": f"bad >= {FAIL}", "go": targets["lose"]})
    rest = "next" if "next" in possible else ("lose" if "lose" in possible else "pass")
    last = targets[next_key] if rest == "next" else targets[rest]
    return {"if": cases, "else": last} if cases else last


SWIPES = [c.clip(f"swipes/{f}", sfx=True) for f in A["swipes"]]


def swipe_for(key):
    """One fixed swipe, chosen by name (where a random one would mean a pre-mix per swipe)."""
    return SWIPES[zlib.crc32(key.encode()) % len(SWIPES)]


def bed(field, volume):
    return c.bed(A[field], volume)


# ----- Jessica's lines, rendered up front -----

FIRST_WELCOME = ("Welcome to Alien Customs. Listen to the rules and talk to the customs officer and convince him to "
                 "let you through. If you answer incorrectly twice, it's game over! Are you ready to play? ")
WELCOME_BACK = "Welcome back to Alien Customs! You are currently on level {n}, {name}. Are you ready to play? "
REPEAT_OR_PLAY = "Repeat, or play? "
lines = [FIRST_WELCOME, REPEAT_OR_PLAY, "Are you ready to play? ", "Are you ready to play Alien Customs? ",
         "Say repeat to hear the rules again, or play to start. ", "The officer needs a yes or no answer. "] + \
    F["dangerWarnings"] + [WELCOME_BACK.format(n=k + 1, name=lv["name"]) for k, lv in enumerate(LEVELS)] + \
    [f"Listen carefully, there is an announcement about {NAMES[i]}. Remember what the officer says! "
     for lv in LEVELS for i in lv["itemIds"]]
print(f"rendering {len(set(lines))} lines in Jessica's voice (cached ones are skipped)...")
c.tts_many(lines)

nodes = {}
ready = say("Are you ready to play? ")

# Launch (doAlienCustomsIntro): the level the player is on.
nodes["level_intro"] = {"redirect": [{"when": f"level == {k}", "go": f"L{k}_intro"} for k in range(1, len(LEVELS))],
                        "go": "L0_intro"}

for k, lv in enumerate(LEVELS):
    # The first two levels get the full welcome (the skill: completedLevelIds.length <= 1).
    welcome = FIRST_WELCOME if k <= 1 else WELCOME_BACK.format(n=k + 1, name=lv["name"])
    nodes[f"L{k}_intro"] = {
        "say": [bed("background", 0.20), say(welcome)],
        "ask": {"reprompt": [ready],
                "answers": [{"yes": True, "words": ["play", "start", "let's go", "go"], "go": f"L{k}_start"},
                            {"no": True, "rank": 1, "go": {"end": "quit"}}],
                "else": {"say": [say("Are you ready to play Alien Customs? ")]},
                "buttons": YES_NO},
    }
    # doAlienCustomsStartGame: the level's items in a random order, each announced first.
    anns = [f"{SUFFIX[i]}_ann" for i in lv["itemIds"]]
    nodes[f"L{k}_start"] = {"set": {"item": 0, "deck_items": ""}, "go": {"draw": anns, "deck": "items"}}

    intro_dialogue = louder(dialogue(lv["introAudioKey"], lv["intro"]), 1.5, f"intro-{k}")
    for item in lv["itemIds"]:
        x = SUFFIX[item]
        flow = ITEMS[item]["questions"]
        rules = F["ruleCounts"].get(item, 3)

        # doAlienCustomsAnnouncement.
        # The announcement sound under Slug's intro and first two rules (after a second's silence).
        layers, t = [{"step": c.clip(A["announcement"], sfx=True)}], 1.0
        for part in (slug(f"{x}-rules-intro"), slug(f"{x}-rule-1"), swipe_for(x), slug(f"{x}-rule-2")):
            layers.append({"step": part, "at": t})
            t += part["dur"]
        first_two = c.mix(f"rules-{x}", layers)
        nodes[f"{x}_ann"] = {
            "say": [bed("background", 0.20),
                    say(f"Listen carefully, there is an announcement about {NAMES[item]}. Remember what the officer says! "),
                    first_two,
                    *([{"pick": [[s] for s in SWIPES]}, slug(f"{x}-rule-3")] if rules >= 3 else []),
                    {"pause": 0.5}, say(REPEAT_OR_PLAY)],
            "ask": {"reprompt": [say(REPEAT_OR_PLAY)],
                    "answers": [{"words": ["play", "play to start", "next", "skip", "start", "go"], "go": f"{x}_start"},
                                {"yes": True, "go": f"{x}_start"},
                                {"repeat": True, "go": f"{x}_ann"},
                                {"words": ["again"], "go": f"{x}_ann"},
                                {"no": True}],
                    "else": {"say": [say("Say repeat to hear the rules again, or play to start. ")]},
                    "buttons": [{"label": "Repeat", "value": "repeat"}, {"label": "Play", "value": "play"}]},
        }

        # doAlienCustomsStartGameAfterAnnouncement: the level's intro before its first item, the officer's "what
        # have we here", and the first question.
        ordinals = {"0": "first", "1": "middle", "2": "final"}
        nodes[f"{x}_start"] = {
            "set": {"ok": 0, "bad": 0},
            "say": [bed("background", 0.20), c.bed(A["item"], 1.0),
                    dict(intro_dialogue, when="item == 0"),
                    {"by": "item", "cases": {i: [{"pick": [[dialogue(f"ordinal-{cat}-{n}")] for n in range(1, 6)]}]
                                             for i, cat in ordinals.items()}},
                    dialogue(f"{x}-q1", flow[0]["officer"])],
            "go": f"{x}_q0",
        }

        # Only what can happen: a round ends at 3 right or 2 wrong (or after the last question), so later
        # questions, and clearing an item after one or two answers, never come up.
        asked, results = round_states(len(flow))
        for i in sorted(asked):
            q = flow[i]
            question = dialogue(f"{x}-q{i + 1}", q["officer"])
            right, wrong = f"{x}_r{i}", f"{x}_w{i}"
            nodes[f"{x}_q{i}"] = {
                "ask": {"reprompt": [question],
                        "answers": [{"yes": True, "go": right if q["correct"] == "yes" else wrong},
                                    {"no": True, "rank": 1, "go": right if q["correct"] == "no" else wrong}],
                        "else": {"say": [{"pause": 0.3}, say("The officer needs a yes or no answer. ")]},
                        "buttons": YES_NO},
            }
            reply_right = dialogue(f"{x}-q{i + 1}-right", q["rightReply"])
            reply_wrong = dialogue(f"{x}-q{i + 1}-wrong", q["wrongReply"])
            targets = {"pass": f"{x}_pass{i}", "lose": f"{x}_lose", "next_r": f"{x}_rc{i}", "next_w": f"{x}_wc{i}"}
            nodes[right] = {"set": {"ok": "+1"}, "go": outcome(results[(i, "r")], targets, "next_r", i, len(flow))}
            nodes[wrong] = {"set": {"bad": "+1"}, "go": outcome(results[(i, "w")], targets, "next_w", i, len(flow))}
            if "next" in results[(i, "r")] or "next" in results[(i, "w")]:
                nxt = dialogue(f"{x}-q{i + 2}", flow[i + 1]["officer"])
            # doNextAlienPrompt: a swipe (right) or the fail sound (wrong) under the reply, a warning after the
            # first mistake, and the next question.
            if "next" in results[(i, "r")]:
                nodes[f"{x}_rc{i}"] = {
                    "say": [bed("background", 0.20),
                            c.mix(f"{x}-r{i}", [{"step": swipe_for(f"{x}-r{i}")}, {"step": reply_right, "at": 1.0}]),
                            nxt],
                    "go": f"{x}_q{i + 1}"}
            if "next" in results[(i, "w")]:
                nodes[f"{x}_wc{i}"] = {
                    "say": [bed("background", 0.20),
                            c.mix(f"{x}-w{i}", [{"step": c.clip(A["fail"], sfx=True)}, {"step": reply_wrong, "at": 1.0}]),
                            dict({"pick": [[say(t)] for t in F["dangerWarnings"]]}, when="bad == 1"),
                            nxt],
                    "go": f"{x}_q{i + 1}"}
            # The item is cleared: on to the next item (doNextAlienQuestion), or the level is won.
            if "pass" in results[(i, "r")] | results[(i, "w")]:
                nodes[f"{x}_pass{i}"] = {"set": {"item": "+1"},
                                         "go": {"if": [{"when": "item >= 3", "go": f"L{k}_win"}], "else": f"{x}_next{i}"}}
                nodes[f"{x}_next{i}"] = {
                    "say": [bed("background", 0.20), c.bed(A["item"], 1.0), reply_right,
                            dialogue(f"{x}-round-pass"), {"bed": None}],
                    "go": {"draw": anns, "deck": "items"}}

        # doAlienCustomsGameOver, lost: access denied, the item's failure, deported.
        denied = dialogue("denied")
        fail = dialogue(f"{x}-round-fail")
        deported = dialogue("deported")
        nodes[f"{x}_lose"] = {
            "say": [bed("background", 0.20), c.bed(A["lose"], 1.0), {"pause": 1.0},
                    c.mix(f"deported-{x}", [{"step": denied, "volume": 2.0},
                                            {"step": fail, "at": denied["dur"], "volume": 1.05},
                                            {"step": deported, "at": denied["dur"] + fail["dur"], "volume": 1.2}])],
            # Try again: this item's level (not level_intro: `level` can point elsewhere after a PLAY AGAIN).
            "end": {"kind": "gameover", "title": "Deported!", "retry": f"L{k}_intro"},
        }

    # doAlienCustomsGameOver, won: the next level. After the free levels, the next one is in the pack; after the
    # last level of all, the skill starts again from level 1.
    title = f"Level {k + 1} cleared: {lv['name'].capitalize()}!"
    if k + 1 < len(LEVELS):
        end = {"kind": "chapter", "title": title, "next": f"L{k + 1}_intro"}
    elif len(LEVELS) < len(F["levels"]):
        end = {"kind": "chapter", "title": title, "next": f"L{k + 1}_intro", "locked": "alien-customs-levels"}
    else:
        end = {"kind": "chapter", "title": f"All {len(LEVELS)} levels cleared!", "next": "level_intro"}
    # The level won, by number: "+1" drifted once `level` wasn't k (PLAY AGAIN at a locked end replays level 1).
    nodes[f"L{k}_win"] = {
        "set": {"level": k + 1 if k + 1 < len(F["levels"]) else 0},
        "say": [bed("background", 0.20), c.bed(A["win"], 1.0), {"pause": 0.8}, dialogue("win")],
        "end": end,
    }

game_map = {
    "format": 1,
    "id": GAME,
    "title": "Alien Customs",
    "start": "level_intro",
    "vars": {"level": 0, "item": 0, "ok": 0, "bad": 0, "deck_items": ""},
    "keep": ["level"],
    "repeat": "reprompt",
    "who": {HOST: "", "OFFICER": "Officer", "SLUG": "Slug"},
    "words": words(YES, NO,
                   ["repeat", "repeat that", "say that again", "say it again", "what did you say", "come again",
                    "pardon", "one more time"]),
    "nodes": nodes,
}
out = OUT / "map.json" if OUT else ROOT / "games" / GAME / "map.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(game_map, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
n_files, size = c.size_report()
print(f"{GAME}: {len(nodes)} nodes, {n_files} audio files, {size / 1e6:.1f} MB -> {out}")
