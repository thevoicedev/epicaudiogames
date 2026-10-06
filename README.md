# Epic Audio Games

Voice-only audio games for Android: put on headphones, listen, and answer out loud, by typing, or with a tap.
Every word is shown on screen as it's spoken. Everything plays offline. Website: epicaudiogames.com.

## How it fits together

| Folder | What's in it |
|---|---|
| `docs/MAP_FORMAT.md` | the game map format: every game is a JSON graph of turns |
| `games/<id>/` | each game's map (`map.json`) and, from phase 4, its packs (`pack.json`) |
| `content/<id>/` | each game's audio, built by the tools and kept out of git |
| `tools/` | build tools: turn the Mini Games radio plays into maps, fetch the audio, check everything |
| `android/` | the app: `engine` (pure Kotlin: maps, answers, saves; tested on the JVM) and, from phase 2, `app` |

The games come from Mini Games (the `all-minigames-sites` repo next to this one, or `MINIGAMES_DIR`), which the
tools read at build time only. Nothing from it runs in the app, and the tools never write to it.

## Building the content

Needs Node, Python 3 with `requests` (for the Mini Games mixer), and ffmpeg. From the repo root:

```
node tools/extract_flows.js     # reads each game's flow and word lists out of the skill code -> tools/flows/
python tools/build_maps.py      # lays the radio plays out with the Mini Games mixer (tools/rp_timings.py) and
                                #   writes games/<id>/map.json, with every line's text, speaker and start time
python tools/fetch_audio.py     # the audio: from the lossless masters where they made the live CDN files,
                                #   else the CDN files themselves -> content/<id>/ (AAC; --codec opus to compare)
python tools/validate.py        # checks every map against the format, and every clip and its length
node tools/parity.js            # plays random walks, and every question with every word it takes, through the
                                #   real Alexa skill (stubbed, offline) -> tools/cache/parity/
```

## The engine

```
cd android
gradlew :engine:test                                       # the tests below
gradlew :engine:run --args="noodle-rush" --console=plain   # play a game by typing
```

The tests:

- **MapsTest:** a bot tries every answer in every state of every map. It must reach every node and every end.
- **ParityTest:** playthroughs written from the skills' code.
- **AlexaReplayTest:** replays the walks `parity.js` recorded in the real skill. Every turn must play the same clips
  as Alexa did, apart from a short list of deliberate differences, each with its reason.
- **TextTest:** the number, letter and negation readers ported from the skills.

## The app

```
cd android
gradlew :app:assembleDebug        # app/build/outputs/apk/debug/app-debug.apk (about 70 MB)
gradlew :app:assembleRelease      # app/build/outputs/apk/release/app-release.apk (about 52 MB, shrunk; signed with
                                  #   the debug key for now, so for testing only)
adb install -r app/build/outputs/apk/release/app-release.apk
```

The games, their audio and their covers ship inside the app for now. The build takes `games/` and `content/` as
assets, so run the content tools first. The app needs Android 7 (API 24) or later.

- **Game list:** each game's cover, description and what's free, with CONTINUE on games left part-way.
- **Game screen:** the talking circle (the game's picture: it pulses while the game speaks, rings while it
  listens, and a tap skips). The transcript appears line by line as it is spoken, with the words still to come
  paler. The answers: buttons, typing or the mic. Answers work while the voice is still talking, and stop it.
- **Listening:** after each question the mic opens by itself, as on Alexa. Silence plays the question again; a
  second silence, or "stop", pauses the game until a tap.
- **Saves:** each game's place is saved at every question, and "Welcome back!" picks it up.

Emulator: the `EpicAudioGames_Pixel` AVD (Android 15, 6 GB of storage) was made for this app. The other AVDs on this
machine are full of other apps' builds.

## Phases

1. The map format, the engine, and the three radio plays: King of Frootopia (story 1), Noodle Rush and Signal
   Decoders. **Done.**
2. The Android app: the game list, the game screen, audio, speech, transcripts and answer buttons. **Running**
   (on the emulator; speech to be tried on a phone; store listing draft in `docs/STORE_LISTING.md`).
3. The ElevenLabs voice, and Pirate Quest, Leaning Tower of Pizza, Alien Customs and The Werewolf.
4. Packs and purchases (Google Play Billing; packs downloaded from our own storage).
5. Nuclear War, a size pass, and the release build.
