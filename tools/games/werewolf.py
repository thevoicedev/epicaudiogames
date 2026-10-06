"""Builds games/the-werewolf/map.json: The Werewolf, stories 1 to 5 (the free ones; 6 to 50 come in a pack).

Each node mirrors one of the skill's headless responses (alexa/lambda/Games/the-werewolf/index.js): a story is
offered ("Time to choose a mystery"), its 8 villagers speak one at a time ("Villager 1 of 8. The Baker."), and the
player names the werewolf. A wrong guess jails a villager and the werewolf eats another; the first werewolf found
means there is one more; finding both wins, and running out of villagers loses. What each villager says depends on
who is jailed, eaten or found: tools/extract_games.js turns the stories' code into conditions on the variables.

The nodes are the same for every story. Variables say which story is playing: its villagers in order (o1 to o8),
its werewolves (w1, w2) and what has happened to each villager (st_<villager>: 0 in play, 1 eaten, 2 in jail, 3 a
werewolf found). The stories' own words sit in `by: story` and `by: off` steps, so a pack of more stories replaces
the nodes that hold them (offer, offer_first, offer_next, offer_yes and c1 to c8) and adds its s<k>_start nodes.

Differences from the skill, on purpose:
- no coins, play limits or "play again, or a different game?": the end screen asks;
- "You can't choose <what was said>" is "You can't choose that" (the app has no live voice);
- "You already discovered the The Baker was a werewolf" and "The The Baker was already eaten" lose the extra "the";
- stories above 5 aren't offered (they are in the pack): "no" after story 5 offers story 1 again, and a number
  picks only stories 1 to 5;
- the villager list at the guess is one clip per name, and "Villager 3 of 8" and the name are two clips (the skill
  says each in one go); unclear answers at the start say "Are you ready to play?";
- "pause" (60 seconds of silence on Alexa) is left to the app's own pause;
- story 2's beggar says his own last line (the skill points it at a recording that doesn't exist).

Usage (from the repo root): python tools/games/werewolf.py   (after node tools/extract_games.js the-werewolf)
The whole game, for its pack (tools/make_pack.py): python tools/games/werewolf.py --stories 50 --build build/packs
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import Content, HOST  # noqa: E402
from skill import words  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GAME = "the-werewolf"
F = json.loads((ROOT / "tools" / "flows" / f"{GAME}.json").read_text(encoding="utf-8"))
A, SP, CH, META = F["audio"], F["speech"], F["characters"], F["meta"]
FREE = 5                                   # stories in the base game
PACK = "the-werewolf-stories"              # the rest of them
ap = argparse.ArgumentParser()
ap.add_argument("--stories", type=int, default=FREE, help="stories to build (all of them: 50)")
ap.add_argument("--build", help="a folder for a pack build: the map and its audio go to <build>/the-werewolf/")
ARGS = ap.parse_args()
STORIES = F["stories"][:ARGS.stories]
N = len(STORIES)
OUT = Path(ARGS.build) / GAME if ARGS.build else None
# The free game's ends offer the pack.
LOCKED = {"locked": PACK} if N < len(F["stories"]) else {}
KEYS = list(CH)                            # baker, fisherman, mayor, barmaid, farmer, butcher, beggar, blacksmith
POS = range(1, 9)                          # a villager's place in the story's order
NAME = {k: CH[k]["name"] for k in KEYS}    # "The Baker"
VOICE = {k: CH[k]["voice"] for k in KEYS}  # "the baker"
WERE = {k: CH[k]["wereName"] for k in KEYS}
PRONOUN = {k: CH[k]["pronoun"] for k in KEYS}


def cid(k):
    """The skill's id for a villager ("_BAKER"), which keys its audio tables."""
    return "_" + k.upper()


# Who speaks the recorded clips, by folder: the story lines and each villager's comments.
COMMENTS = ["caught-comments", "long-found-comments", "little-found-comments", "were-go-comments",
            "little-positive-comments", "werewolf_denials"]
voices = {f"{s['id']}/{k}/": k.upper() for s in STORIES for k in KEYS}
voices.update({f"{folder}/{k}/": k.upper() for folder in COMMENTS for k in KEYS})
voices.update({f"confused/{k}": k.upper() for k in KEYS})
voices.update({f"werewolf-found/{k}": k.upper() for k in KEYS})
voices[A["intro"]] = "NARRATOR"            # "The werewolf."
c = Content(GAME, F["cdn"], voices=voices, out=OUT / "content" if OUT else None,
            fixes={"=Dover": "Bother", "=Father": "Bother",
                   "#DeliciousVillager @McDonald's @PizzaHut. So fresh":
                       "Hashtag Delicious Villager. At McDonald's. At Pizza Hut. So fresh!"})

YES_NO = [{"label": "Yes", "value": "yes"}, {"label": "No", "value": "no"}]
PLAY = ["play", "start", "play again", "begin", "again", "=lion"]    # the skill's PLAY_UTTERANCES
NEXT = ["next", "nest", "neck", "skip"]                              # its checkNextMatch, and "skip"
LIST = ["list", "list villagers", "village", "villager", "villagers"]


def synonyms(k):
    """What counts as naming a villager: the skill's synonyms (kids' mishears included), its name and key."""
    out = {s.lower() for s in CH[k]["synonyms"]} | {VOICE[k], k}
    out |= {f"={said}" for said, meant in F["exactAliases"].items() if meant == VOICE[k]}
    return sorted(out)


def say(text):
    return c.tts(text)


def fx(rel):
    """Music or a sound effect."""
    return c.clip(rel, sfx=True)


def heard(rel):
    """A recording whose words the code doesn't have: speech-to-text gives them (none: a sound effect)."""
    return c.clip(rel)


def by(var, cases, otherwise=None, when=None):
    step = {"by": var, "cases": {str(k): v for k, v in cases.items()}}
    if otherwise is not None:
        step["else"] = otherwise
    if when:
        step["when"] = when
    return step


def pick(options):
    return {"pick": options}


def when(cond, step):
    return dict(step, when=cond) if cond else step


def go_if(cases, otherwise):
    return {"if": [{"when": w, "go": g} for w, g in cases], "else": otherwise}


def strip_tags(text):
    """A story line as shown: its performance tags ("[nervously]") out, as the skill's screen shows it."""
    return re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", " ", text)).strip()


def stat(i):
    """What has happened to the villager at place i of the story playing (its st_ variable)."""
    return " : ".join(f'o{i} == "{k}" ? st_{k}' for k in KEYS[:-1]) + f" : st_{KEYS[-1]}"


# a1 to a8: whether the villager at each place is still in play; n: how many are.
REFRESH = {f"a{i}": f"=({stat(i)}) == 0" for i in POS}
REFRESH["n"] = "=" + " + ".join(f"a{i}" for i in POS)

# The werewolf eats a villager in play who isn't a werewolf, at random (getRandomElement of allActiveNoWere): the kv-th
# of the nv candidates (60 is a multiple of every count up to 6, so each is as likely). After the jailing.
KILL = {f"a{i}": REFRESH[f"a{i}"] for i in POS}
KILL.update({f"iv{i}": f"=a{i} && !wf{i}" for i in POS})
KILL["nv"] = "=" + " + ".join(f"iv{i}" for i in POS)
KILL["r"] = "rand(0,59)"
KILL["kv"] = "=nv > 0 ? r % nv + 1 : 0"
KILL["victim"] = "=" + " : ".join(f"iv{i} && {' + '.join(f'iv{j}' for j in range(1, i + 1))} == kv ? o{i}"
                                  for i in POS) + ' : ""'
KILL.update({f"st_{k}": f'=victim == "{k}" ? 1 : st_{k}' for k in KEYS})
KILL["n"] = "=" + " + ".join(f"a{i}" for i in POS) + ' - (victim != "")'

# The villager last named is g; gst is what has happened to them (their st_).
G_STATUS = {"gst": "=" + " : ".join(f'g == "{k}" ? st_{k}' for k in KEYS[:-1]) + f" : st_{KEYS[-1]}"}

# The messages for naming a villager who is out of play (getWerewolfAlreadyChosenMessage), by their st_.
ALREADY = {3: lambda k: f"You already discovered {NAME[k]} was a werewolf. ",
           2: lambda k: "You already threw them in jail! ",
           1: lambda k: f"{NAME[k]} was already eaten by the werewolf! "}
READY_VILLAGERS = "Are you ready to talk to the villagers? "
GUESS_HELP = "Guess the werewolf, or say: list villagers. "


def names(go_in_play, go_out, rank=1):
    """An answer for each villager named (it sets g to them): one while they are in play, one once they're out."""
    out = []
    for k in KEYS:
        out.append({"words": synonyms(k), "rank": rank, "when": f"st_{k} == 0", "set": {"g": k}, "go": go_in_play})
        out.append({"words": synonyms(k), "rank": rank, "when": f"st_{k} != 0", "set": {"g": k}, "go": go_out})
    return out


def already(extra=""):
    """What to say for g, named while out of play: by who they are, then by what happened to them."""
    return by("g", {k: [by("gst", {v: [say(f(k) + extra)] for v, f in ALREADY.items()})] for k in KEYS})


def build():
    nodes = {}
    ambience = A["ambience"]

    # ----- The start, and the story offer -----

    # Launch (doPlayTheWerewolf), or a new night after a game (doReplayTheWerewolf).
    nodes["begin"] = {"redirect": [{"when": "plays > 0", "go": "replay"}], "go": "intro"}
    nodes["intro"] = {
        "say": [heard(A["intro"]), c.bed(A["background"], 1.0),
                say("A murder has taken place in a village by a werewolf. Interview the villagers, before the "
                    "werewolf strikes again. Are you ready to play? ")],
        "ask": {"reprompt": [say("Are you ready to play? ")],
                "answers": [{"yes": True, "words": PLAY + ["the werewolf", "werewolf"], "go": "offer_first"},
                            {"no": True, "rank": 1, "go": {"end": "quit"}}],
                "else": {"say": [say("Are you ready to play? ")]},
                "buttons": YES_NO},
    }
    nodes["replay"] = {
        "say": [heard(A["intro"]), c.bed(A["background"], 1.0),
                say("Another night. Lo' and behold, the werewolf strikes again. "), {"bed": None}],
        "go": "offer_first",
    }

    # getOrderedUnsolvedStoryIds: unsolved stories, the ones not played yet first, in story order (all solved: every
    # story again, in order). The offer walks that list with "no" and wraps round (doOfferWerewolfStory).
    ks = range(1, N + 1)
    first = {"allsv": "=" + " && ".join(f"sv{k}" for k in ks)}
    first.update({f"sv{k}": f"=allsv ? false : sv{k}" for k in ks})
    first.update({f"r{k}": f"=sv{k} ? 100 : (us{k} && !allsv ? {10 + k} : {k})" for k in ks})
    first["rmin"] = "=min(" + ", ".join(f"r{k}" for k in ks) + ")"
    first["off"] = "=" + " : ".join(f"r{k} == rmin ? {k}" for k in ks if k < N) + f" : {N}"
    first["ofirst"] = True
    first["oid"] = 0
    nodes["offer_first"] = {"set": first, "go": "offer"}
    nxt = {"rcur": "=" + " : ".join(f"off == {k} ? r{k}" for k in ks if k < N) + f" : r{N}",
           "rn": "=min(" + ", ".join(f"r{k} > rcur && r{k} < 100 ? r{k} : 1000" for k in ks) + ")",
           "rt": "=rn == 1000 ? rmin : rn",
           "nr": "=" + " : ".join(f"r{k} == rt ? {k}" for k in ks if k < N) + f" : {N}",
           # After a story picked by number, the offer walks the stories in order (the skill's allIds).
           "ni": f"=off % {N} + 1",
           "ofirst": "=oid == 1 ? ni == 1 : rt == rmin",
           "off": "=oid == 1 ? ni : nr"}
    nodes["offer_next"] = {"set": nxt, "go": "offer"}
    for k in ks:
        nodes[f"offer_n{k}"] = {"set": {"off": k, "oid": 1, "ofirst": k == 1}, "go": "offer"}

    def offer_text(k, first_one):
        m = META[f"s{k}"]
        lead = "Time to choose a mystery. How about this: " if first_one else ""
        return f"{lead}{m['name']}. {m['plot']} Do you want to play? "

    nodes["offer"] = {
        "say": [c.bed(ambience, 0.30),
                by("off", {k: [say(offer_text(k, True))] for k in ks}, when="ofirst"),
                by("off", {k: [say(offer_text(k, False))] for k in ks}, when="!ofirst")],
        "ask": {"reprompt": [say("Want to play? ")],
                "answers": [{"yes": True, "words": PLAY, "go": "offer_yes"},
                            {"no": True, "words": NEXT, "rank": 1, "go": "offer_next"},
                            {"repeat": True, "go": "offer"},
                            *[{"digits": str(k), "exact": True, "go": f"offer_n{k}"} for k in ks]],
                "else": "offer",
                "buttons": YES_NO},
    }
    nodes["offer_yes"] = {"go": go_if([(f"off == {k}", f"s{k}_start") for k in ks], "s1_start")}

    # doStartWerewolfGame: the story's name over the start music, a roar, and the first villager.
    for k, s in enumerate(STORIES, 1):
        w1, w2 = s["werewolves"]
        start = {"story": k}
        start.update({f"o{i}": key for i, key in enumerate(s["order"], 1)})
        start.update({"w1": w1, "w2": w2, "wp": f"{w1}-{w2}", "wq": f"{w2}-{w1}"})
        start.update({f"wf{i}": key in s["werewolves"] for i, key in enumerate(s["order"], 1)})
        start.update({f"st_{key}": 0 for key in KEYS})
        start.update({f"l{i}": 0 for i in POS})
        start.update({"found": 0, "first_jail": "", "pending": "", "victim": "", "pq": 0})
        name = META[s["id"]]["name"]
        first_name = NAME[s["order"][0]]
        hello = (f"There are 8 villagers, each one has a different story of last night's events. Want to talk to "
                 f"{first_name}? " if s["id"] == "s1" else f"First up is {first_name}. Want to talk to them? ")
        nodes[f"s{k}_start"] = {
            "set": start,
            "say": [c.mix(f"start-{s['id']}", [{"step": fx(A["werewolfStart"]), "volume": 0.6, "trim": True},
                                               {"step": say(f"{name}. "), "at": 2.0}]),
                    fx(A["miniRoar"]), c.bed(ambience, 0.30), say(hello)],
            "go": "prompt",
        }

    # ----- "Are you ready to talk to the villagers?" (PROMPT_VILLAGERS) -----

    nodes["prompt"] = {
        "ask": {"reprompt": [by("o1", {key: [say(f"Want to talk to {NAME[key]}? ")] for key in KEYS}, when="pq == 0"),
                             when("pq == 1", say(READY_VILLAGERS)),
                             when("pq == 2", say("Want to talk to the villagers? "))],
                # Naming a villager here guesses them straight away.
                "answers": [*names("jail", "pal"),
                            {"yes": True, "words": NEXT + PLAY + ["matt"], "go": "round"},
                            {"no": True, "go": "decline"}],
                "else": {"say": [say(READY_VILLAGERS)]},
                "buttons": YES_NO},
    }
    nodes["pal"] = {"set": G_STATUS, "say": [already(READY_VILLAGERS)], "go": "prompt"}

    # ----- The villagers, one at a time (doPlayCurrentWerewolfCharacter) -----

    nodes["round"] = {"set": {**REFRESH, "idx": 0}, "go": "p1"}
    for i in POS:
        nodes[f"p{i}"] = {"redirect": [{"when": f"!a{i}", "go": f"p{i + 1}" if i < 8 else "guess"}],
                          "set": {"pos": i, "cur": f"=o{i}", "vkey": "=(idx + 1) * 10 + n"},
                          "go": "vintro"}
    pairs = [(v, m) for m in range(2, 9) for v in range(1, m)]
    nodes["vintro"] = {
        "say": [c.bed(ambience, 0.30),
                by("cur", {key: [say(f"Final Villager. {NAME[key]}")] for key in KEYS}, when="idx >= n - 1"),
                by("vkey", {f"{v}{m}": [pick([[say(t.replace("{v}", f"Villager {v} of {m}") + ". ")]
                                              for t in SP["hereComes"]])] for v, m in pairs}, when="idx < n - 1"),
                by("cur", {key: [say(f"{NAME[key]}. ")] for key in KEYS}, when="idx < n - 1")],
        "go": go_if([(f"pos == {i}", f"c{i}") for i in POS], "c1"),
    }

    def line(s, key, v):
        # One line in the skill names another villager's recording (story 2's beggar says "butcher-4-1", which
        # isn't on the CDN, so Alexa plays nothing): the villager's own recording of that number is used.
        own = "fish" if key == "fisherman" else key
        rec = v["id"] if v["id"].startswith(own + "-") else own + "-" + v["id"].split("-", 1)[1]
        step = c.clip(f"{s['id']}/{key}/{rec}.mp3", text=strip_tags(v["text"]), who=key.upper(), check=True)
        return when(v["when"], step)

    for i in POS:
        cases = {}
        for k, s in enumerate(STORIES, 1):
            key = s["order"][i - 1]
            said = s["lines"][key]
            # A villager who has said every line says the last one again.
            cases[k] = [fx(A["characters"][cid(key)]),
                        by(f"l{i}", {j: [line(s, key, v) for v in said[j]] for j in range(len(said) - 1)},
                           otherwise=[line(s, key, v) for v in said[-1]])]
        nodes[f"c{i}"] = {"say": [by("story", cases), {"pause": 1.0}, say("Repeat, or next. ")], "go": f"a{i}"}
        nodes[f"r{i}"] = {"say": [c.bed(ambience, 0.30)], "go": f"c{i}"}       # doRepeatCurrentWerewolfChar
        nodes[f"a{i}"] = {
            "ask": {"reprompt": [say("Repeat, or next. ")],
                    "answers": [{"yes": True, "words": NEXT + PLAY + ["=red"], "go": f"n{i}"},
                                {"repeat": True, "go": f"r{i}"},
                                {"no": True, "go": f"r{i}"},
                                # Naming a villager before hearing everyone: "are you sure?"
                                *names("cf", "gal")],
                    "else": f"r{i}",
                    "buttons": [{"label": "Repeat", "value": "repeat"}, {"label": "Next", "value": "next"}]},
        }
        nodes[f"n{i}"] = {"set": {f"l{i}": "+1", "idx": "+1"},
                          "go": go_if([("idx >= n", "guess")], f"p{i + 1}" if i < 8 else "guess")}
    nodes["rep"] = {"go": go_if([(f"pos == {i}", f"r{i}") for i in POS], "r1")}
    nodes["nxt"] = {"go": go_if([(f"pos == {i}", f"n{i}") for i in POS], "n1")}
    nodes["gal"] = {"set": G_STATUS, "say": [already()], "go": "rep"}

    # WEREWOLF_CONFIRM_GUESS: pending is the villager named.
    sure = by("pending", {key: [say(f"Are you sure it's {NAME[key]}? ")] for key in KEYS})
    nodes["cf"] = {"set": {"pending": "=g"},
                   "say": [by("g", {key: [say(f"You haven't listened to all the villagers yet. Are you sure it's "
                                              f"{NAME[key]}? ")] for key in KEYS})],
                   "go": "cfa"}
    nodes["cf2"] = {"set": {"pending": "=g"}, "say": [sure], "go": "cfa"}
    nodes["cfal"] = {"set": G_STATUS, "say": [already(), sure], "go": "cfa"}
    nodes["cfa"] = {
        "ask": {"reprompt": [sure],
                "answers": [{"yes": True, "set": {"g": "=pending"}, "go": "jail"},
                            {"no": True, "set": {"pending": ""}, "go": "rep"},
                            {"words": NEXT, "rank": 1, "set": {"pending": ""}, "go": "nxt"},
                            *names("cf2", "cfal")],
                "else": {"say": [sure]},
                "buttons": YES_NO},
    }

    # ----- "Who do you think is the werewolf?" (doGuessWerewolfCharacter) -----

    remaining = by("n", {v: [say(f"There are {v} villagers remaining. ")] for v in range(1, 8)}, when="n < 8")
    villagers = []                     # getWerewolfRemainingCharsText: "the baker, the mayor or the farmer."
    for i in POS:
        later = " + ".join(f"a{j}" for j in range(i + 1, 9)) or "0"
        villagers.append(by(f"o{i}", {key: [say(f"{VOICE[key]}, ")] for key in KEYS}, when=f"a{i} && {later} > 0"))
        villagers.append(by(f"o{i}", {key: [say(f"or {VOICE[key]}. ")] for key in KEYS}, when=f"a{i} && {later} == 0"))
    who_is_it = say("Who do you think is the werewolf? ")
    nodes["guess"] = {
        "set": REFRESH,
        "say": [c.bed(ambience, 0.35), pick([[say(t)] for t in SP["werewolfCharsFinished"]]), remaining, *villagers,
                who_is_it],
        "go": "ga",
    }
    nodes["ga"] = {
        "ask": {"reprompt": [say("Who is the werewolf? ")],
                "answers": [{"words": LIST, "rank": 2, "go": "glist"},
                            {"repeat": True, "rank": 2, "go": "glist"},
                            {"re": r"\bguess\b.*\bwerewolf\b", "rank": 2, "go": "glist"},
                            *names("jail", "gual"),
                            *[{"digits": str(v), "exact": True, "go": f"gnum{v}"} for v in POS],
                            {"yes": True, "go": "ghuh"}, {"no": True, "go": "ghuh"}],
                "else": {"say": [say("You can't choose that. " + GUESS_HELP)]},
                "buttons": [{"label": "List villagers", "value": "list villagers"}]},
    }
    nodes["glist"] = {"say": [remaining, *villagers, who_is_it], "go": "ga"}
    nodes["ghuh"] = {"say": [say(GUESS_HELP)], "go": "ga"}
    # Checked in the skill's order (dead, then jail): a werewolf found is in jail too.
    nodes["gual"] = {
        "set": G_STATUS,
        "say": [by("g", {key: [by("gst", {1: [say(f"{NAME[key]} has already been killed by the werewolf! " + GUESS_HELP)]},
                                  otherwise=[say(f"{NAME[key]} has already been put in jail! " + GUESS_HELP)])]
                         for key in KEYS})],
        "go": "ga"}
    # A number picks the villager in that place of the list (doPickWerewolfNumber).
    for v in POS:
        nodes[f"gnum{v}"] = {"redirect": [{"when": f"n < {v}", "go": "ghuh"}], "set": {"want": v, "seen": 0},
                             "go": "gn1"}
    chose = by("want", {v: [by("g", {key: [say(f"You chose villager {v}, {VOICE[key]}. ")] for key in KEYS})]
                        for v in POS})
    for i in POS:
        nodes[f"gn{i}"] = {"set": {"seen": f"=seen + a{i}"},
                           "go": go_if([(f"a{i} && seen == want", f"gch{i}")], f"gn{i + 1}" if i < 8 else "ghuh")}
        nodes[f"gch{i}"] = {"set": {"g": f"=o{i}"}, "say": [chose], "go": "jail"}

    # ----- A guess (doWerewolfGuess): g is the villager -----

    nodes["jail"] = {"set": {"first_jail": '=first_jail == "" ? g : first_jail', "pending": ""},
                     "go": go_if([("w1 == g || w2 == g", "wolf")], "inn")}
    nodes["wolf"] = {"set": {**{f"st_{k}": f'=g == "{k}" ? 3 : st_{k}' for k in KEYS}, "found": "+1",
                             "after": "wolf1"},
                     "go": go_if([("found >= 2", "win")], "kill")}
    nodes["inn"] = {"set": {**{f"st_{k}": f'=g == "{k}" ? 2 : st_{k}' for k in KEYS}, "after": "inn"}, "go": "kill"}
    nodes["decline"] = {"set": {"after": "decline"}, "go": "kill"}
    nodes["kill"] = {"set": KILL, "go": go_if([('after == "wolf1"', "wolf1_say"), ('after == "decline"', "decline_go")],
                                              "inn_go")}

    chuck = by("g", {key: [say(f"You chuck {VOICE[key]} in jail! ")] for key in KEYS})
    key_lock = fx(A["keyLocking"])
    denial = by("g", {key: [pick([[c.mix(f"deny-{key}-{j}", [{"step": key_lock},
                                                             {"step": heard(f"werewolf_denials/{key}/{j}.mp3")}])]
                                  for j in range(1, 6)])] for key in KEYS})

    # doPutVillagerInPrison: the wrong villager is jailed and another is eaten; with too few villagers left, the
    # werewolves take over.
    nodes["inn_go"] = {"go": go_if([("n <= 2 || n <= 3 && found == 0", "takeover")], "inn_say")}
    nodes["inn_say"] = {
        "set": {"pq": 1},
        "say": [c.bed(ambience, 0.30), {"pause": 1.0}, fx(A["throw"]), chuck, denial, fx(A["wolfKills"]),
                by("victim", {key: [say(f"{VOICE[key]} was eaten. ")] for key in KEYS}), fx(A["gasp"]),
                say("The werewolf is still around. "), fx(A["mediSting"]), say(READY_VILLAGERS)],
        "go": "prompt",
    }
    confused = {key: [heard(f"confused/{A['confusedComments'][cid(key)]}")] for key in KEYS}
    nodes["takeover"] = {
        "say": [c.bed(ambience, 0.30), {"pause": 1.0}, fx(A["throw"]), chuck, denial,
                c.mix("look", [{"step": fx(A["horrorRiser"])}, {"step": say("You look at the remaining villagers. ")}]),
                pick([[by("w1", confused)], [by("w2", confused)]]), {"bed": None}],
        "go": "lose",
    }

    # doFoundWerewolfOneMore: the first werewolf is jailed, a villager is eaten, and there is one more.
    found = by("g", {key: [heard(f"werewolf-found/{A['werewolfFound'][cid(key)]}")] for key in KEYS})
    shrunk = by("g", {key: [say(f"The {WERE[key]} has shrunk back. ")] for key in KEYS})
    chuck_them = by("g", {key: [say(f"You chuck {PRONOUN[key]} in jail! ")] for key in KEYS})
    nodes["wolf1_say"] = {
        "set": {"pq": 1},
        "say": [heard(A["wereCorect"]), found, c.bed(ambience, 0.20), say("You found the werewolf. "), fx(A["shrink"]),
                shrunk,
                by("g", {key: [pick([[heard(f"caught-comments/{key}/{f}")] for f in A["caughtComments"][cid(key)]])]
                         for key in KEYS}),
                fx(A["throw"]), chuck_them, key_lock, fx(A["heartbeat"]),
                by("victim", {key: [say(f"Grave News. {NAME[key]} was eaten! ")] for key in KEYS}), fx(A["gasp"]),
                say("That means... "), fx(A["scarySting"]),
                by("g", {key: [say(f"{VOICE[key]} wasn't the only werewolf. There is one more werewolf to find. ")]
                         for key in KEYS}),
                {"pause": 1.0}, say(READY_VILLAGERS)],
        "go": "prompt",
    }

    # "No" to talking to the villagers (doDeclineVillagerPrompt): the werewolf eats one while you wait.
    casual = pick([[say(t)] for t in SP["casualWait"]])
    bad = pick([[c.mix(f"bad-{j}", [{"step": fx(A["repeatKill"])}, {"step": say(t), "at": 3.5}])]
                for j, t in enumerate(SP["badPhrases"])])
    got_eaten = by("victim", {key: [say(f"{NAME[key]} got eaten. ")] for key in KEYS})
    nodes["decline_go"] = {"go": go_if([("n <= 3", "decline_end")], "decline_say")}
    nodes["decline_say"] = {
        "set": {"pq": 2},
        "say": [c.bed(ambience, 0.25), casual, bad, say("Well. Good job. "), {"pause": 0.5}, got_eaten, fx(A["gasp"]),
                {"pause": 0.5}, say("I hope you're happy. Can we talk to the villagers now please? ")],
        "go": "prompt",
    }
    nodes["decline_end"] = {
        "say": [c.bed(ambience, 0.25), casual, bad, say("Well. Good job. "), {"pause": 0.5},
                when('victim != ""', got_eaten), fx(A["gasp"]), {"bed": None}],
        "go": "lose",
    }

    # ----- The end (doWerewolfGameOver) -----

    played = {f"us{k}": f"=story == {k} ? true : us{k}" for k in ks}
    music = c.bed_of(c.mix("game-over-music", [{"step": fx(A["gameOver"]), "fade_in": 2.0}]), 0.25)
    wolf_pairs = sorted({(a, b) for s in STORIES for a, b in (s["werewolves"], s["werewolves"][::-1])})

    def per_villager(folder, table):
        return {key: [pick([[heard(f"{folder}/{key}/{f}")] for f in A[table][cid(key)]])] for key in KEYS}

    long_found = per_villager("long-found-comments", "longFoundComments")
    little_found = per_villager("little-found-comments", "littleFoundComments")
    you_found = {f"{a}-{b}": [say(f"You found the {WERE[a]} and the {WERE[b]}. ")] for a, b in wolf_pairs}
    nodes["win"] = {
        "set": {**{f"sv{k}": f"=story == {k} ? true : sv{k}" for k in ks}, **played, "plays": "+1"},
        "say": [heard(A["wereCorect"]), found, c.bed(ambience, 0.25), fx(A["shrink"]), shrunk, fx(A["throw"]),
                chuck_them, key_lock, {"bed": None},
                music, heard(A["winFx"]),
                pick([[by("wp", you_found), by("w1", long_found), by("w2", little_found)],
                      [by("wq", you_found), by("w2", long_found), by("w1", little_found)]]),
                fx(A["expandFx"])],
        "end": {"kind": "ending", "title": "You caught both werewolves!", **LOCKED},
    }
    go_comments = per_villager("were-go-comments", "gameOverComments")
    positive = per_villager("little-positive-comments", "littlePositiveComments")
    grunt = pick([[fx(f"were-go-comments/grunts/{f}")] for f in A["grunts"]])
    were_wolves = {f"{a}-{b}": [c.mix(f"were-{a}-{b}", [{"step": fx(A["expandFx"])},
                                                        {"step": say(f"{VOICE[a]} and {VOICE[b]} were werewolves. "),
                                                         "at": 1.0}])]
                   for a, b in wolf_pairs}
    nodes["lose"] = {
        "set": {**played, "plays": "+1"},
        "say": [music, heard(f"were-go-comments/{A['gameOverFx']}"), say("Game over. "),
                pick([[by("wp", were_wolves), by("w1", go_comments), grunt, by("w2", positive)],
                      [by("wq", were_wolves), by("w2", go_comments), grunt, by("w1", positive)]])],
        "end": {"kind": "gameover", "title": "The werewolves got away!", "retry": "replay", **LOCKED},
    }
    return nodes


nodes = c.prepare(build)

variables = {"story": 0, "w1": "", "w2": "", "wp": "", "wq": "", "found": 0, "first_jail": "", "n": 0, "idx": 0,
             "pos": 0, "cur": "", "vkey": 0, "pending": "", "g": "", "gst": 0, "victim": "", "after": "", "pq": 0, "r": 0,
             "nv": 0, "kv": 0, "want": 0, "seen": 0, "plays": 0, "off": 0, "ofirst": False, "oid": 0, "allsv": False,
             "rmin": 0, "rcur": 0, "rn": 0, "rt": 0, "nr": 0, "ni": 0}
for i in POS:
    variables.update({f"o{i}": "", f"wf{i}": False, f"l{i}": 0, f"a{i}": False, f"iv{i}": False})
for key in KEYS:
    variables[f"st_{key}"] = 0
for k in range(1, N + 1):
    variables.update({f"sv{k}": False, f"us{k}": False, f"r{k}": 0})

game_map = {
    "format": 1,
    "id": GAME,
    "title": "The Werewolf",
    "start": "begin",
    "vars": variables,
    "keep": [f"sv{k}" for k in range(1, N + 1)] + [f"us{k}" for k in range(1, N + 1)] + ["plays"],
    "repeat": "reprompt",
    "who": {HOST: "", "NARRATOR": "Narrator", **{key.upper(): CH[key]["display"] for key in KEYS}},
    "words": words(["yes", "yeah", "yep", "yup", "sure"], ["no", "nope", "nah"],
                   ["repeat", "repeat that", "say that again", "say it again", "what did you say", "come again",
                    "pardon", "one more time"]),
    "nodes": nodes,
}
out = OUT / "map.json" if OUT else ROOT / "games" / GAME / "map.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(game_map, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
n_files, size = c.size_report()
print(f"{GAME}: {len(nodes)} nodes, {n_files} audio files, {size / 1e6:.1f} MB -> {out}")
if c.differs:
    print(f"{len(c.differs)} recorded lines say other words than the code (the heard words are shown):")
    for path, code, said in c.differs:
        print(f"  {path}\n    code:  {code}\n    heard: {said}")
