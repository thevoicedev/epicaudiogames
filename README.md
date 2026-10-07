# Epic Audio Games

Voice-only audio games for Android and iPhone: put on headphones, listen, and answer out loud, by typing, or by
tapping one of the options shown in the chat.
Every word is shown on screen as it's spoken. Everything plays offline. Website: epicaudiogames.com.

## How it fits together

| Folder | What's in it |
|---|---|
| `docs/MAP_FORMAT.md` | the game map format: every game is a JSON graph of turns |
| `games/<id>/` | each game's map (`map.json`) and, from phase 4, its packs (`pack.json`); Nuclear War, written in Kotlin, has its clips (`clips.json`) and lines (`lines.json`) instead |
| `content/<id>/` | each game's audio, built by the tools (committed, with the tools' cache in `tools/cache/`, so no voice is paid for twice) |
| `tools/` | build tools: turn the Mini Games radio plays into maps, fetch the audio, check everything |
| `android/` | the app: `engine` (pure Kotlin: maps, answers, saves, and Nuclear War; tested on the JVM) and, from phase 2, `app` |
| `web/` | the website, epicaudiogames.com: one page, served by a dependency-free Node server on Railway (see below) |
| `ios/` | the iPhone app, in Swift: the engine ported from Kotlin and checked against it, and the SwiftUI app (`docs/IOS.md`) |
| `fixtures/engine/` | what the Kotlin engine does, written by its tests and replayed by the Swift engine (`docs/IOS_PARITY.md`) |

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

The coded games (Leaning Tower of Pizza, Alien Customs, The Werewolf and Pirate Quest) are built from the skill's
own tables and a builder per game, which mirrors the skill's responses node by node:

```
node tools/extract_games.js [game]       # the game's tables, speech lists and audio names -> tools/flows/<game>.json
python tools/games/<game>.py             # the map and its audio -> games/<id>/map.json, content/<id>/
python tools/prune.py --game <id>        # drops audio the map no longer plays
node tools/capture.js "<launch>" yes ... # prints what the real skill plays on a path (its mixers, clips and lines),
                                         #   to check a builder against
```

**Nuclear War** is too much game for a map (five countries' money, cities, sanctions and bombs, and what the
computer countries decide each round), so it's written in Kotlin: `android/engine/.../nuclear/NuclearWar.kt` is the
skill's code ported function by function, speaker path only. Its announcer is Don (ElevenLabs "Don - Movie Trailer
Narrator", the user's pick): `Lines.kt` holds everything he says, and every line is one clip found by its words.
Lines with a city, a country or a small number have a clip per value; lists of cities, money and points are said in
pieces, each rendered inside a whole sentence and cut out of it between words, then joined in the transcript.
Numbers are read as words (the clips are cut by ElevenLabs' character times, which aren't reliable for digits).

```
node tools/extract_games.js nuclear-war                      # the skill's audio table -> tools/flows/nuclear-war.json
cd android && gradlew :engine:run --args="--nuclear-lines"   # Don's lines -> games/nuclear-war/lines.json
python tools/games/nuclearwar.py                             # -> games/nuclear-war/clips.json, content/nuclear-war/
python tools/games/nuclearwar_check.py                       # speech-to-text on every Don clip: what to listen to
```

**Packs** (more stories and levels, bought in the app): a builder run with `--build build/packs` and all the
stories or levels (`aliencustoms.py --levels 15`, `werewolf.py --stories 50`; for Frootopia,
`build_maps.py --cached --frootopia-stories 5 --build build/packs` then `fetch_audio.py --game frootopia --build
build/packs`) writes the whole game there; then
`tools/make_pack.py` cuts the pack out of it: `games/<id>/packs/<pack>.json` (the nodes the free map doesn't have),
`dist/packs/<pack>-<version>.zip` (that and its audio, for the pack server) and the pack's line in
`games/catalog.json` (title, Play product id, size, checksum).

`tools/content.py` makes every clip a builder uses: Alexa's lines in the app's voice (ElevenLabs, Jessica, or Don
for Nuclear War, with the time of every word), the skill's recordings from the Mini Games CDN (speech-to-text gives
their words and times; `check=True` compares them with the words in the code, and `turns=True` splits a scene into
a line per speaker turn), beds, and pre-mixed overlaps. Everything is cached
in `tools/cache/`, so a rebuild only renders what changed. The ElevenLabs key comes from `ELEVENLABS_API_KEY` or
`all-minigames-sites/alexa/.env` and is never printed.

## The engine

```
cd android
gradlew :engine:test                                       # the tests below
gradlew :engine:run --args="noodle-rush" --console=plain   # play a game by typing (nuclear-war too)
```

The tests:

- **MapsTest:** a bot tries every answer in every state of every map (up to a limit, then 3,000 random games). It
  must reach every node and every end.
- **ParityTest**, **LtopTest**, **AlienCustomsTest**, **WerewolfTest**, **PirateQuestTest:** playthroughs written
  from the skills' code and the responses `capture.js` recorded.
- **AlexaReplayTest:** replays the walks `parity.js` recorded in the real skill. Every turn must play the same clips
  as Alexa did, apart from a short list of deliberate differences, each with its reason.
- **NuclearWarTest:** 3,000 bot games of Nuclear War with random answers. Every game must end, Don must say
  only lines from `Lines.kt` (and, with the audio made, every one has its clip), every question must have its
  reprompt, and a save must pick up again.
- **TextTest:** the number, letter and negation readers ported from the skills.

## The app

```
cd android
gradlew :app:assembleDebug        # app/build/outputs/apk/debug/app-debug.apk (about 190 MB with eight games)
gradlew :app:assembleRelease      # app/build/outputs/apk/release/app-release.apk (about 52 MB, shrunk; signed with
                                  #   the debug key for now, so for testing only)
adb install -r app/build/outputs/apk/release/app-release.apk
```

The games, their audio and their covers ship inside the app for now. The build takes `games/` and `content/` as
assets, so run the content tools first. The app needs Android 7 (API 24) or later.

- **Game list:** each game's cover, description and what's free, with CONTINUE on games left part-way.
- **Game screen:** the talking circle (the game's picture: it pulses while the game speaks, rings while it
  listens, and a tap skips). The transcript appears line by line as it is spoken, with the words still to come
  paler; a line that carries on a sentence (the speaker's line before it ends with a comma or is marked to carry
  on, as in a list of names read one clip per name) joins that bubble. The answers: the mic or typing, or a tap on
  one of the question's options, shown as chips at the end of the chat. Answers work while the voice is still
  talking, and stop it.
- **Listening:** after each question the mic opens by itself, as on Alexa. Silence plays the question again; a
  second silence, or "stop", pauses the game until a tap.
- **Screen off, phone in a pocket:** while a game is open it keeps talking and listening (a foreground service,
  with a notification showing the game and its cover). The headphones' button (play/pause) does what a tap on the
  talking circle does: skip, talk, stop listening, or carry on. Pause (the lock screen's, or earbuds taken out)
  pauses the game; play carries on, or talks when it's your turn. With a Bluetooth headset, the
  game listens through the headset's mic. Calls, other apps taking the audio and headphones coming out still pause.
- **Saves:** each game's place is saved at every question, and "Welcome back!" picks it up.
- **Packs:** a game's card and menu open its store sheet: each pack's price (Google Play Billing), buying it, then
  downloading it from the pack server (`-PepicPacksUrl=https://...`, or `epicPacksUrl` in gradle.properties),
  checking it against the catalog and unpacking it into the app's files. Purchases made before are restored the same
  way. A locked chapter end offers its pack. Debug builds also install any `<pack>-<version>.zip` pushed to
  `/sdcard/Android/data/com.epicaudiogames.app/files/incoming/`, to try packs without the store or a server.

Emulator: the `EpicAudioGames_Pixel` AVD (Android 15, 6 GB of storage) was made for this app. The other AVDs on this
machine are full of other apps' builds.

## The website

`web/` is epicaudiogames.com: one page (`public/index.html`, with the covers, the social preview image and the
Hugo FM footer) served by `server.js`, a Node server with no dependencies. It lives in the `epicaudiogames.com`
project on Railway, as the `web` service.

```
node web/server.js                               # http://localhost:3000 (PORT to change it)
railway up web --path-as-root --service web      # deploy; `railway link` first on a new machine
```

`CANONICAL_HOST=epicaudiogames.com` on the service makes `www.` redirect to the bare domain.

**The pack server** is the same server: `https://epicaudiogames.com/packs/<pack>-<version>.zip`, from the folder
`PACKS_DIR` (default `web/packs/`), with ranges (a broken-off download carries on) and a year's caching (Cloudflare,
in front of Railway, keeps them too). Both apps are built with `https://epicaudiogames.com/packs`: Android's
`epicPacksUrl` (`-PepicPacksUrl=https://epicaudiogames.com/packs`, or in `~/.gradle/gradle.properties`) and iOS's
`EPIC_PACKS_URL` (`ios/Config/Local.xcconfig`). The apps install a zip only if its size and SHA-256 are the ones in
the `games/catalog.json` they were built with, so a published zip is never replaced: a changed pack is a new version
(`make_pack.py --version 2`), and the old zip stays for the builds that still ask for it.

`railway up` leaves the zips out (`web/.railwayignore`: they are 173 MB, and it turns big uploads away with "File too
large"), so on Railway they live on a volume. Once, after `railway link`:

```
railway volume --service web add --mount-path /data     # a volume on the web service, at /data
railway variable set PACKS_DIR=/data/packs --service web
railway up web --path-as-root --service web             # the server that serves /packs/
```

Then, for each new zip in `dist/packs/` (no deploy needed; `railway volume list` gives the volume's name; without
`--overwrite`, a zip already there isn't replaced, as it shouldn't be):

```
for f in dist/packs/*.zip; do railway volume files --volume <name> upload "$f" "/data/packs/${f##*/}"; done
railway volume files --volume <name> list /data/packs
curl -sI https://epicaudiogames.com/packs/the-werewolf-stories-1.zip     # 200, Content-Length as in the catalog
```

To try packs locally: `PACKS_DIR=dist/packs node web/server.js`, and point the simulator at `http://localhost:3000/packs`.

## Phases

1. The map format, the engine, and the three radio plays: King of Frootopia (story 1), Noodle Rush and Signal
   Decoders. **Done.**
2. The Android app: the game list, the game screen, audio, speech, transcripts and answer buttons. **Running**
   (on the emulator; speech to be tried on a phone; store listing draft in `docs/STORE_LISTING.md`).
3. The ElevenLabs voice (Jessica), and Pirate Quest, Leaning Tower of Pizza, Alien Customs (levels 1 to 5) and
   The Werewolf (stories 1 to 5). **Done.**
4. Packs and purchases (Google Play Billing; packs downloaded from our own storage). **Running:** the pack format,
   the app's store and pack downloads, and the three packs are made and tried on the emulator: Alien Customs levels
   6 to 15 (26 MB), The Werewolf stories 6 to 50 (133 MB) and The Kingdom of Frootopia stories 2 to 5 (15 MB). Still
   to come: the pack server, and the products in the Play Console.
5. Nuclear War, a size pass, and the release build. **Running:** Nuclear War is done (the whole game, in Don's
   voice; see above). Still to come: the size pass and the release build (it needs the upload signing key).
6. The iPhone app (`docs/IOS.md`). **Running:** every game, speech, saves, packs (StoreKit 2) and VoiceOver work in
   the simulator, and the Swift engine replays the Kotlin one exactly. A bug hunt on both apps fixed 99 bugs in
   both. Still to come: trying it on a phone with the real audio, the products in App Store Connect, and the release.
