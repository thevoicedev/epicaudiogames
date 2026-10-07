"""Builds games/leaning-tower-of-pizza/map.json: Leaning Tower of Pizza, Battle and Challenge modes.

Each node mirrors one of the skill's responses (alexa/lambda/Games/leaning-tower-of-pizza/index.js): its music bed
(`bed` steps: the skill's trimToParent audio), its recorded clips and Alexa's lines (now Jessica's), in the same
order, and its nested mixers pre-mixed (content.mix). Random picks stay random (`pick`), the score lines follow the
score (`by`), and questions come from decks that don't repeat until they run out, kept between plays, as the
skill keeps its used-question lists.

Differences from the skill, on purpose:
- no coins, no play limits and no online leaderboard (rank lines); "play again, or a different game?" is the
  app's end screen;
- the high-score reply plays its two lines one after the other (the skill mixes them, so they overlap);
- challenge mode's nose-grow sound is grow-nose.mp3 (the skill asks for ltop-nose-grow.mp3, which isn't on the CDN);
- number lines are rendered up to 60 (streaks, best scores); beyond that a line without the number.

Usage (from the repo root): python tools/games/ltop.py   (after node tools/extract_games.js leaning-tower-of-pizza)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import Content, HOST  # noqa: E402
from skill import NO, YES, words  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GAME = "leaning-tower-of-pizza"
F = json.loads((ROOT / "tools" / "flows" / f"{GAME}.json").read_text(encoding="utf-8"))
A, S, SHARED = F["audio"], F["speech"], F["sharedSpeech"]
WIN, GROWTH, MAX_Q = F["rules"]["win"], F["rules"]["growth"], F["rules"]["maxQuestions"]
TOF = F["truthOrLie"][0]
TOP = 60                      # number lines rendered up to here

# Gepetto has his own folder; everything else that speaks is the pizza robot, taunting (in a mock-Italian accent).
c = Content(GAME, F["cdn"], voices={"gepetto/": "GEPETTO", "monster": "ROBOT", "never-stop": "ROBOT",
                                    "lose-comments": "ROBOT", "fx/robot": "ROBOT", "correct-reactions/": "ROBOT",
                                    "wrong-reactions/": "ROBOT", "one-away-reactions/": "ROBOT"},
            fixes={"Agrande canal": "Grand Canal"})

# parseTrueFalse: "true" (or "too") first, then "false" and its mishears; YesIntent is true, NoIntent false; a
# "2" (PickNumber) is true.
TRUE_WORDS = ["true", "too", "two", "2"]
FALSE_WORDS = ["false", "lie", "lye", "force", "balls", "both", "pause"]
# The mode question: high scores first, then challenge, then battle (the skill checks them in that order).
SCORE_WORDS = ["high score", "high scores", "highscore", "highscores", "scores", "score", "leaderboard"]
CHALLENGE_WORDS = ["challenge", "challenges", "charge", "george"]
BATTLE_WORDS = ["battle", "battles", "bottle"]
YES_NO = [{"label": "Yes", "value": "yes"}, {"label": "No", "value": "no"}]
MODES = [{"label": "Battle", "value": "battle"}, {"label": "Challenge", "value": "challenge"}]


# ----- Steps -----

def say(text):
    return c.tts(text)


def rec(field, texts=None):
    """A recorded clip from the skill's table: the one file, or a random one of a list (with its known texts)."""
    files = A[field]
    if isinstance(files, str):
        return c.clip(files, text=texts)
    clips = [c.clip(f, text=texts[i] if texts else None) for i, f in enumerate(files)]
    return {"pick": [[x] for x in clips]}


def pick_say(texts):
    return {"pick": [[say(t)] for t in texts]}


def bed(field, volume):
    return c.bed(A[field], volume)


def when(cond, *steps):
    return [dict(s, when=cond) for s in steps]


def numbered(var, template, lo, hi=TOP, fallback=None, scale=1):
    """A line with the variable's value in it, for each value from lo to hi ("Your streak was 7!")."""
    cases = {str(n): [say(template.format(n=n * scale))] for n in range(lo, hi + 1)}
    return {"by": var, "cases": cases, "else": [say(fallback)] if fallback else []}


def ranges(var, bands):
    """Steps by the variable's range: [(lo, hi, steps)], hi None for no top."""
    out = []
    for lo, hi, steps in bands:
        cond = f"{var} >= {lo}" + (f" && {var} <= {hi}" if hi is not None else "")
        out += [dict(s, when=cond) for s in steps]
    return out


# ----- Everything Jessica says, rendered up front in parallel -----

QUESTIONS = [(pool, q) for pool in ("main", "easy", "trick", "dn") for q in F["questions"][pool]]
ALL_LINES = [q["statement"] for _, q in QUESTIONS] + [q["fact"] for _, q in QUESTIONS if q.get("fact")] + [TOF] + \
    S["WRONG_ANSWER_FOLLOWUPS"] + S["ONE_MORE_LIE_ENCOURAGEMENTS"] + S["CORRECT_LIE_REACTIONS"] + \
    S["CHALLENGE_GAME_OVER"] + SHARED["winSavedTown"] + [
        "Pinocchio, we need you to save Venice from the evil pizza robot. ",
        "It is out of control, and flooding venice with pizzas. ",
        "Say lies and grow your nose, to press the big red off button next to the pizza robot. ",
        "I will ask you true or false questions, and you need to lie about the answer. "
        "If the answer is True, say false. And if the answer is false, say true. Are you ready to play? ",
        "Are you ready to play? ", "Let's save the city! ", "Let's play! ",
        "You've just unlocked challenge mode! ",
        "Practice with Gepetto and try to get as many lies in a row as you can! Want to play? ",
        "Would you like to try challenge mode? ",
        "Welcome back Pinocchio! Want to play Battle or Challenge mode? ", "Battle or Challenge? ",
        "Want to play challenge or battle mode? ", "You haven't set a high score in challenge mode yet! ",
        f"You took more than {MAX_Q} guesses and didn't save the city in time! ",
        "You scored 0 points! ", "You scored 1 point! ",
    ] + [f"Only {WIN - n} metres to go! " for n in range(GROWTH, WIN, GROWTH)] + \
    [f"{WIN - n} metres to go! " for n in range(0, WIN, GROWTH)] + \
    [f"Your best challenge mode streak is {n}! " for n in range(1, TOP + 1)] + \
    [f"Your best challenge mode streak is {n}. " for n in range(2, TOP + 1)] + \
    [f"Your nose is {n * 10} metres long. " for n in range(1, TOP + 1)] + \
    [f"Your streak was {n}! " for n in range(2, TOP + 1)] + \
    [f"Your all time best is {n}! " for n in range(2, TOP + 1)] + [
        f"Your best challenge mode streak is more than {TOP}! ", f"Your best challenge mode streak is more than {TOP}. ",
        f"Your nose is more than {TOP * 10} metres long. ", f"Your streak was more than {TOP}! ",
        f"Your all time best is more than {TOP}! "]
print(f"rendering {len(set(ALL_LINES))} lines in Jessica's voice (cached ones are skipped)...")
c.tts_many(ALL_LINES)

# ----- Nodes -----

nodes = {}
q_id = {q["id"]: f"q_{q['id']}" for _, q in QUESTIONS}
deck = {pool: [q_id[q["id"]] for q in F["questions"][pool]] for pool in ("main", "easy", "trick", "dn")}


def draw(pool):
    return {"draw": deck[pool], "deck": pool}


# Launch (doLaunchLtopGame): the first play's intro, else the mode question once challenge mode is unlocked.
nodes["start"] = {"redirect": [{"when": "!firstDone", "go": "first_intro"}, {"when": "unlocked", "go": "mode_select"}],
                  "go": "battle"}

# doLtopFirstPlayIntro.
ready = say("Are you ready to play? ")
throwing = c.clip(A["throwing"], sfx=True)
nodes["first_intro"] = {
    "set": {"firstDone": True},
    "say": [bed("background", 0.25),
            say("Pinocchio, we need you to save Venice from the evil pizza robot. "),
            rec("monster"),
            say("It is out of control, and flooding venice with pizzas. "),
            c.mix("say-lies", [{"step": throwing},
                               {"step": say("Say lies and grow your nose, to press the big red off button next to the pizza robot. "), "at": 3.0}]),
            rec("robotNono"),
            # The skill joins back-to-back lines into one utterance.
            say("I will ask you true or false questions, and you need to lie about the answer. "
                "If the answer is True, say false. And if the answer is false, say true. Are you ready to play? ")],
    "ask": {"reprompt": [ready], "answers": [{"yes": True, "go": "battle"}, {"no": True, "go": {"end": "quit"}}],
            "else": {"say": [ready]}, "buttons": YES_NO},
}

# doStartLtop: a battle starts with an easy question.
nodes["battle"] = {
    "set": {"nose": 0, "guesses": 0, "mode": "battle"},
    "say": [bed("background", 0.25), bed("throwLoop", 0.35), rec("monsterIntro"), say("Let's save the city! ")],
    "go": draw("easy"),
}

# The questions (each pool's), the same node in both modes: what follows depends on the mode.
for pool, q in QUESTIONS:
    lie_if_true = not q["isTrue"]           # saying "true" to a false statement is a lie
    statement = say(q["statement"])
    question = [statement, {"pause": 0.5}, say(TOF)]
    nodes[q_id[q["id"]]] = {
        "set": {"q": q["id"]},
        "say": question,
        "ask": {
            "reprompt": [say(TOF)],
            # "not true" is a false and "not false" a true (each answer's opposite); a mishear said with "not" is
            # neither ("not too sure").
            "answers": [
                {"words": TRUE_WORDS[:1], "rank": 2, "opposite": 2, "go": "lie" if lie_if_true else "honest"},
                {"words": TRUE_WORDS[1:], "rank": 2, "go": "lie" if lie_if_true else "honest"},
                {"words": FALSE_WORDS[:1], "rank": 1, "opposite": 0, "go": "honest" if lie_if_true else "lie"},
                {"words": FALSE_WORDS[1:], "rank": 1, "go": "honest" if lie_if_true else "lie"},
                {"yes": True, "go": "lie" if lie_if_true else "honest"},
                {"no": True, "go": "honest" if lie_if_true else "lie"},
                {"repeat": True, "go": q_id[q["id"]]},
            ],
            "else": {"say": question},
            "buttons": [{"label": "True", "value": "true"}, {"label": "False", "value": "false"}],
        },
    }

# doProcessTrueFalseAnswer: a lie grows the nose; the battle is won at 50 metres, lost after 15 answers.
nodes["lie"] = {"redirect": [{"when": 'mode == "challenge"', "go": "c_lie"}],
                "set": {"nose": f"+{GROWTH}", "guesses": "+1"},
                "go": {"if": [{"when": f"nose >= {WIN}", "go": "win"}, {"when": f"guesses >= {MAX_Q}", "go": "lose"}],
                       "else": "lie_react"}}
nodes["honest"] = {"redirect": [{"when": 'mode == "challenge"', "go": "c_over"}],
                   "set": {"guesses": "+1"},
                   "go": {"if": [{"when": f"guesses >= {MAX_Q}", "go": "lose"}], "else": "honest_react"}}

grow = c.clip(A["growNose"], sfx=True)
lie_mixes = {}
for nose in range(GROWTH, WIN, GROWTH):
    left = WIN - nose
    only = say(f"Only {left} metres to go! ")
    lie_mixes[str(nose)] = [{"pick": [[c.mix(f"lie-{left}", [
        {"step": say(r)},
        {"step": grow, "at": 0.5, "fade_in": 0.5},
        {"step": only, "at": 0.5 + grow["dur"]}])] for r in S["CORRECT_LIE_REACTIONS"]]}]
nodes["lie_react"] = {
    "say": [bed("background", 0.25), rec("correctPing"),
            {"by": "nose", "cases": lie_mixes},
            *when(f"nose == {WIN - GROWTH}", rec("oneAwayReactions"), pick_say(S["ONE_MORE_LIE_ENCOURAGEMENTS"])),
            *when(f"nose != {WIN - GROWTH}", rec("correctReactionsVoice")),
            bed("throwLoop", 0.35)],
    "go": "next_q",
}

wrong_ping = c.clip(A["wrongPing"], sfx=True)
nodes["honest_react"] = {
    "say": [bed("background", 0.25),
            {"pick": [[c.mix("wrong", [{"step": wrong_ping}, {"step": c.clip(f)}])] for f in A["wrongReactionsVoice"]]},
            pick_say(S["WRONG_ANSWER_FOLLOWUPS"]),
            {"by": "nose", "cases": {str(n): [say(f"{WIN - n} metres to go! ")] for n in range(0, WIN, GROWTH)}},
            bed("throwLoop", 0.35)],
    "go": "next_q",
}

# The next question: the 1st is easy, the 4th a trick, and on the very first battle the last one (the one that
# can win it) is a double negative.
nodes["next_q"] = {"go": {"if": [{"when": "guesses == 0", "go": draw("easy")},
                                 {"when": "guesses == 3", "go": draw("trick")},
                                 {"when": f"plays == 0 && nose == {WIN - GROWTH}", "go": draw("dn")}],
                          "else": draw("main")}}

# doLtopWin.
nodes["win"] = {
    "set": {"plays": "+1"},
    "say": [bed("background", 0.30), rec("neverStop"), pick_say(SHARED["winSavedTown"]), {"bed": None}],
    "go": {"if": [{"when": "!unlocked", "go": "unlock"}], "else": "won"},
}
nodes["won"] = {"end": {"kind": "ending", "title": "You saved Venice!"}}

# The challenge mode unlock, after the first win.
u1 = say("You've just unlocked challenge mode! ")
u2 = rec("challengeUnlock")
u3 = say("Practice with Gepetto and try to get as many lies in a row as you can! Want to play? ")
t = 1.5
layers = [{"step": c.clip(A["unlockFx"], sfx=True)}]
for st in (u1, u2, u3):
    layers.append({"step": st, "at": t})
    t += st["dur"]
try_challenge = say("Would you like to try challenge mode? ")
nodes["unlock"] = {
    "set": {"unlocked": True},
    "say": [c.mix("unlock", layers)],
    "ask": {"reprompt": [try_challenge], "answers": [{"yes": True, "go": "c_start"}, {"no": True, "go": {"end": "quit"}}],
            "else": {"say": [try_challenge]}, "buttons": YES_NO},
}

# doLtopLose.
squelch = c.clip(A["squelch"], sfx=True)
nodes["lose"] = {
    "set": {"plays": "+1"},
    "say": [bed("background", 0.20), c.bed(A["wrongPing"], 1.0),
            {"pick": [[c.mix("lose", [{"step": squelch}, {"step": c.clip(f), "at": 1.7}])] for f in A["loseComments"]]},
            say(f"You took more than {MAX_Q} guesses and didn't save the city in time! ")],
    "end": {"kind": "gameover", "title": "Venice is buried in pizza!", "retry": "start"},
}

# doLtopModeSelect and doShowHighScores.
mode_ask = {
    "reprompt": [say("Battle or Challenge? ")],
    "answers": [{"words": SCORE_WORDS, "rank": 3, "go": "scores"},
                {"words": CHALLENGE_WORDS, "rank": 2, "go": "c_start"},
                {"words": BATTLE_WORDS, "rank": 1, "go": "battle"}],
    "else": {"say": [say("Battle or Challenge? ")]},
    "buttons": MODES,
}
nodes["mode_select"] = {"say": [bed("background", 0.25), say("Welcome back Pinocchio! Want to play Battle or Challenge mode? ")],
                        "ask": mode_ask}
nodes["scores"] = {
    "say": [bed("background", 0.25),
            *when("best >= 1", numbered("best", "Your best challenge mode streak is {n}! ", 1,
                                        fallback=f"Your best challenge mode streak is more than {TOP}! ")),
            *when("best < 1", say("You haven't set a high score in challenge mode yet! ")),
            say("Want to play challenge or battle mode? ")],
    "ask": mode_ask,
}

# doStartChallengeMode: Gepetto's intro (the first time, or one of his welcome-backs), the best streak, and a
# first question that is easy.
nodes["c_start"] = {
    "set": {"mode": "challenge", "streak": 0},
    "say": [bed("challengeInstrumental", 0.25),
            *when("!playedChallenge", rec("challengeIntroFirstTime", S["CHALLENGE_INTRO_FIRST_TIME"])),
            *when("playedChallenge", rec("challengeIntroReturn", S["CHALLENGE_INTRO_RETURN"])),
            *when("best >= 2", numbered("best", "Your best challenge mode streak is {n}. ", 2,
                                        fallback=f"Your best challenge mode streak is more than {TOP}. ")),
            say("Let's play! ")],
    "go": "c_started",
}
nodes["c_started"] = {"set": {"playedChallenge": True}, "go": "c_next_q"}
nodes["c_next_q"] = {"go": {"if": [{"when": "streak == 0", "go": draw("easy")},
                                   {"when": "streak >= 3 && (streak - 3) % 4 == 0", "go": draw("trick")}],
                            "else": draw("main")}}

# doProcessChallengeAnswer: a lie adds to the streak; Gepetto marks the milestones, and cheers a new best when the
# old one was 2 or more.
MILESTONES = [(0, 1, "challengeMilestone1", "CHALLENGE_MILESTONE_1"), (2, 3, "challengeMilestone2_3", "CHALLENGE_MILESTONE_2_3"),
              (4, 5, "challengeMilestone4_5", "CHALLENGE_MILESTONE_4_5"), (6, 10, "challengeMilestone6_10", "CHALLENGE_MILESTONE_6_10"),
              (11, 20, "challengeMilestone11_20", "CHALLENGE_MILESTONE_11_20"), (21, 50, "challengeMilestone21_50", "CHALLENGE_MILESTONE_21_50"),
              (51, 100, "challengeMilestone51_100", "CHALLENGE_MILESTONE_51_100"), (101, None, "challengeMilestone100Plus", "CHALLENGE_MILESTONE_100_PLUS")]
nodes["c_lie"] = {
    "set": {"streak": "+1",
            "newHigh": "=streak > best && streak >= 2 && best >= 2",
            "best": "=streak > best && streak >= 2 ? streak : best"},
    "say": [bed("challengeInstrumental", 0.25), rec("correctPing"), grow,
            *ranges("streak", [(lo, hi, [rec(field, S[texts])]) for lo, hi, field, texts in MILESTONES]),
            *when("newHigh", rec("challengeNewHighscore", S["CHALLENGE_NEW_HIGHSCORE"])),
            *when("!newHigh", numbered("streak", "Your nose is {n} metres long. ", 1, scale=10,
                                       fallback=f"Your nose is more than {TOP * 10} metres long. "), {"pause": 0.5})],
    "go": "c_next_q",
}

# doChallengeGameOver: the first truth ends the challenge; Gepetto, then a game-over line, then the fact behind
# the last question.
facts = {q["id"]: [say(q["fact"])] for pool, q in QUESTIONS if q.get("fact")}
nodes["c_over"] = {
    "set": {"plays": "=streak >= 1 ? plays + 1 : plays", "best": "=streak > best ? streak : best"},
    "say": [bed("challengeInstrumental", 0.20), rec("wrongPing"), rec("wrongBuzzer"),
            rec("challengeGameOver", S["CHALLENGE_GAME_OVER"]), pick_say(S["CHALLENGE_GAME_OVER"]),
            {"by": "q", "cases": facts, "else": []},
            *when("streak >= 2", numbered("streak", "Your streak was {n}! ", 2, fallback=f"Your streak was more than {TOP}! "),
                  numbered("best", "Your all time best is {n}! ", 2, fallback=f"Your all time best is more than {TOP}! ")),
            *when("streak < 2", numbered("streak", "You scored {n} points! ", 0, 0),
                  numbered("streak", "You scored {n} point! ", 1, 1))],
    "end": {"kind": "gameover", "title": "Challenge over!", "retry": "start"},
}

game_map = {
    "format": 1,
    "id": GAME,
    "title": "Leaning Tower of Pizza",
    "start": "start",
    "vars": {"nose": 0, "guesses": 0, "mode": "battle", "streak": 0, "best": 0, "newHigh": False, "plays": 0, "q": "",
             "firstDone": False, "unlocked": False, "playedChallenge": False,
             "deck_main": "", "deck_easy": "", "deck_trick": "", "deck_dn": ""},
    "keep": ["best", "plays", "firstDone", "unlocked", "playedChallenge", "deck_main", "deck_easy", "deck_trick", "deck_dn"],
    "repeat": "reprompt",
    "who": {HOST: "", "GEPETTO": "Gepetto", "ROBOT": "Pizza Robot"},
    # Alexa's own yes and no (the skill's Yes and No intents), and the skill-wide yes/no rules.
    "words": words(YES, NO,
                   ["repeat", "repeat that", "say that again", "say it again", "what did you say", "come again",
                    "pardon", "one more time"]),
    "nodes": nodes,
}
out = ROOT / "games" / GAME / "map.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(game_map, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
n_files, size = c.size_report()
print(f"{GAME}: {len(nodes)} nodes, {n_files} audio files, {size / 1e6:.1f} MB -> {out.relative_to(ROOT)}")
