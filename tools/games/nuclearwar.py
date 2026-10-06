"""Nuclear War's audio, into games/nuclear-war/clips.json and content/nuclear-war/.

The game itself is Kotlin (android/engine/src/main/kotlin/com/epicaudiogames/engine/nuclear/). It says only the
lines in games/nuclear-war/lines.json, each one clip found by its text, and plays the skill's recordings through the
skill's audio table. So this makes:

- voice: every line of lines.json in Don's voice (pieces of sentences rendered with the words around them);
- clips: the recordings the game plays (leaders' calls, themes, effects), speech transcribed;
- table: which recordings each of the skill's audio getters chooses from (tools/flows/nuclear-war.json);
- mixes: the rules, as the skill's tutorial mixer plays them.

Before it: `node tools/extract_games.js nuclear-war`, and (after a change to the lines) from android/:
`gradlew :engine:run --args="--nuclear-lines"`.

Usage (from the repo root): python tools/games/nuclearwar.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from content import DON, ROOT, Content  # noqa: E402

GAME = "nuclear-war"
FLOW = json.loads((ROOT / "tools" / "flows" / f"{GAME}.json").read_text(encoding="utf-8"))
LINES = json.loads((ROOT / "games" / GAME / "lines.json").read_text(encoding="utf-8"))
OUT = ROOT / "games" / GAME / "clips.json"

# Speakers in the transcript: Don (no name shown, as Alexa had none) and the five leaders.
WHO = {"HOST": "", "FR": "Alex Craimant", "US": "Iona Butt", "UK": "Roger Shufflebottom", "CN": "Hoo Flung Dung",
       "RU": "Yuri Poo-tin"}
VOICES = {"nuclear-war/France/": "FR", "nuclear-war/US/": "US", "nuclear-war/UK/": "UK", "nuclear-war/China/": "CN",
          "nuclear-war/Russia/": "RU"}
# Speech-to-text slips, mostly the leaders' names (shown as the skill's screens spelt them).
FIXES = {"=Who flung dung here?": "Hoo Flung Dung here.", "Hu Feng Deng": "Hoo Flung Dung",
         "Alex Cremont": "Alex Craimant", "=Alex Cremant here": "Alex Craimant here.",
         "=I own a butt here": "Iona Butt here.", "=Viva la France.": "Vive la France!",
         "lovely chubly": "lovely jubbly"}

# What NuclearWar.kt plays from the table (the rest of it is for the skill's screens).
COUNTRY_FIELDS = ["Theme", "Representative", "Motivators", "PhoneHello", "SanctionsRemoved", "BombCountry", "Attack",
                  "GeneralChat", "GotBombed", "RemoveSanction", "DefenseSpending", "EnvironmentBad", "Worried",
                  "Friendly", "NuclearBuilding", "Victory"]
MUSIC = {"Theme"}
SFX = ["kaching", "nuclearReactor", "upgradeEnvironment", "research", "shield", "stampFx", "eraser", "pressButton",
       "phoneRing", "shortRing", "pickupPhone", "hangUp", "crickets", "longOrchestral", "deplete", "trumpet", "woosh",
       "alarm", "singleBeep", "dropExplode", "dramaticFx", "orchestralShort", "marching", "triumph", "halo",
       "thunderbolt"]

# Don's lines as Ogg Opus: thousands of short clips, a third smaller than AAC.
c = Content(GAME, "en/audio2/", voices=VOICES, fixes=FIXES, voice=DON, trim=True, opus=True)


def paths(v):
    """Every path in a table value (a path, a list, or names to paths)."""
    if isinstance(v, str):
        return [v]
    if isinstance(v, list):
        return [p for x in v for p in paths(x)]
    return [p for x in v.values() for p in paths(x)]


def table():
    t = FLOW["table"]
    out = {ref: {f: t[ref][f] for f in COUNTRY_FIELDS if f in t[ref]} for ref in ["France", "USA", "UK", "China", "Russia"]}
    out["sfx"] = {k: t["sfx"][k] for k in SFX}
    return out


# ----- The rules (doTutorialSpeech): Don's lines and the effects between them, under the war theme at 30% -----

def say(text):
    return ("say", text)


def sfx(key, volume=1.0):
    return ("sfx", key, volume)


def pause(ms):
    return ("pause", ms / 1000)


TUTORIAL = [
    say("Take charge of 3 cities for 5 rounds."),
    sfx("triplePop"),
    say("They will earn you 3 million each round."),
    ("mix", [say("Assuming they have not been destroyed."), sfx("bombShort", 0.5)]),
    say("You have a starting budget of 10 million."),
    sfx("kaching"),
    ("mix", [say("You will be able to invest 2 million in research in a city."), ("seq", [pause(3000), sfx("research")])]),
    pause(1000),
    say("This will increase the amount you earn from a city each round by 1 million."),
    say("Defense."),
    sfx("shield"),
    say("Invest in a shield for a city for 3 million."),
    pause(1000),
    say("This will protect a city from 1 nuclear strike."),
    pause(1000),
    say("Attack."),
    pause(375),
    say("Before you can make nuclear bombs you will need to develop nuclear tech. This will cost five million."),
    sfx("reactorShort"),
    say("And do 10% damage to the environment."),
    sfx("deplete"),
    say("Once you have nuclear tech you will be able to produce a nuclear bomb for three million. Using a nuclear "
        "bomb is free but it will do 5% damage to the environment."),
    sfx("deplete"),
    say("The environment."),
    sfx("upgradeEnvironment"),
    say("A 10% decrease in the environment will decrease income for every country by half a million."),
    say("You can improve the environment for 1 million. It will give a 10% improvement to the environment which "
        "will give everyone a 750K increase in income."),
    sfx("kaching"),
    pause(1000),
    say("Sanctions."),
    say("You can also sanction countries that you don't like."),
    sfx("stampFx"),
    say("A sanctioned country will get 20% less money every turn."),
    pause(375),
    say("That was a lot of information but it is usually best to learn the game as you play. Let's get started."),
]
TUTORIAL_SFX = {"triplePop", "bombShort", "kaching", "research", "shield", "reactorShort", "deplete",
                "upgradeEnvironment", "stampFx", "orchestralLong"}


def lay(item, at, layers):
    """Puts a tutorial item (and what's in it) at a time; returns how long it lasts."""
    kind = item[0]
    if kind == "pause":
        return item[1]
    if kind == "say":
        step = c.tts(item[1], speak=item[1].replace("750K", "750 thousand"))
        layers.append({"step": step, "at": at})
        return step["dur"]
    if kind == "sfx":
        step = c.clip(FLOW["table"]["sfx"][item[1]], sfx=True)
        layers.append({"step": step, "at": at, "volume": item[2]})
        return step["dur"]
    if kind == "seq":
        t = at
        for x in item[1]:
            t += lay(x, t, layers)
        return t - at
    if kind == "mix":
        return max(lay(x, at, layers) for x in item[1])
    raise ValueError(item)


def tutorial():
    layers = []
    length = lay(("seq", TUTORIAL), 0.0, layers)
    bed = c.clip(FLOW["table"]["sfx"]["orchestralLong"], sfx=True)
    layers.insert(0, {"step": bed, "at": 0.0, "volume": 0.30, "trim": True})
    if c.planning is not None:
        return None
    step = c.mix("tutorial", layers)
    assert abs(step["dur"] - length) < 0.5, (step["dur"], length)
    return step


def build():
    t = table()
    clips = {}
    for ref in ["France", "USA", "UK", "China", "Russia"]:
        for field, v in t[ref].items():
            for p in paths(v):
                clips[p] = c.clip(p, sfx=True) if field in MUSIC else c.clip(p)
    for k, v in t["sfx"].items():
        for p in paths(v):
            clips[p] = c.clip(p, sfx=True)
    voice = {}
    for line in LINES:
        piece = bool(line.get("before") or line.get("after"))
        voice[line["text"]] = c.tts(line["text"], speak=line.get("speak"), before=line.get("before", ""),
                                    after=line.get("after", ""), piece=piece)
    mixes = {"tutorial": tutorial()}
    return {"format": 1, "id": GAME, "title": "Nuclear War", "who": WHO, "table": t, "clips": clips, "voice": voice,
            "mixes": mixes}


def prune():
    """Removes the clips the game no longer plays (lines rendered again, or dropped)."""
    gone = 0
    for f in list(c.dir.rglob("*")):
        rel = f.relative_to(c.dir).with_suffix("").as_posix()
        if f.is_file() and f.name != "cover.jpg" and rel not in c.used:
            f.unlink()
            gone += 1
    return gone


def main():
    data = c.prepare(build)
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{prune()} old clips removed")
    n, size = c.size_report()
    speech = [p for p, s in data["clips"].items() if s.get("lines")]
    print(f"{OUT.relative_to(ROOT)}: {len(data['voice'])} lines of Don's, {len(data['clips'])} recordings "
          f"({len(speech)} with speech); {n} files, {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
