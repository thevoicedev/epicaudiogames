# Epic Audio Games

Voice-only audio games for Android phones and tablets, iPhone and iPad, made for blind and partially sighted players
first: put on headphones, listen, and answer out loud, by typing, or by tapping one of the options shown in the chat.
Every word is shown on screen as it's spoken. Everything plays offline. A Wear OS app and an Apple Watch app are a
remote for the game on the phone. Website: epicaudiogames.com.

## How it fits together

| Folder | What's in it |
|---|---|
| `docs/MAP_FORMAT.md` | the game map format: every game is a JSON graph of turns |
| `docs/DESIGN.md` | the apps' design, for blind and partially sighted players first: colours, type, screens, wording, screen readers, tablets and watches, and the checks on real phones |
| `games/<id>/` | each game's map (`map.json`) and, from phase 4, its packs (`pack.json`); Nuclear War, written in Kotlin, has its clips (`clips.json`) and lines (`lines.json`) instead |
| `content/<id>/` | each game's audio, built by the tools (committed, with the tools' cache in `tools/cache/`, so no voice is paid for twice) |
| `content/app/` | the apps' own sounds and spoken help, the same in both: the intro sting, the listening sounds, the help topics read aloud, and `app.json`, which lists them (`tools/app_audio.py`) |
| `tools/` | build tools: turn the Mini Games radio plays into maps, fetch the audio, make the apps' own sounds, the store art, screenshots and preview video, check everything, and report the usage data (below) |
| `brand/` | what the store art is made from: the palette, fonts and image prompts, the owner's picks, the screenshots' scenes and captions (`scenes.json`, `shots.json`) and the preview video's storyboard (`previews/`); `docs/STORE_ART.md` |
| `android/` | the Android app: `engine` (pure Kotlin: maps, answers, saves, and Nuclear War; tested on the JVM), `app` (phones, tablets and Chromebooks) and `wear` (the Wear OS app, with `wear/link`, what it and the phone app say to each other; `docs/WEAR_OS.md`) |
| `web/` | the website, epicaudiogames.com, and the apps' usage-data API: a small Node server on Railway, with a Postgres database (see below) |
| `ios/` | the iPhone and iPad app, in Swift: the engine ported from Kotlin and checked against it, the SwiftUI app (`docs/IOS.md`), and the Apple Watch app in `ios/EpicWatch/` (`docs/WATCH.md`) |
| `fixtures/engine/` | what the Kotlin engine does, written by its tests and replayed by the Swift engine (`docs/IOS_PARITY.md`) |
| `ios/fastlane/`, `android/fastlane/` | everything the two stores show, as files, and the lanes that upload it (`docs/STORE_LISTING.md`, `docs/STORE_ART.md`); `docs/RELEASE.md` is the release, step by step |

The games come from Mini Games (the `all-minigames-sites` repo next to this one, or `MINIGAMES_DIR`), which the
tools read at build time only. Nothing from it runs in the app, and the tools never write to it.

## Building the content

Needs Node, Python 3 with `requests` (for the Mini Games mixer), and ffmpeg. On the Windows PC that Python is
`py -3.13` (it has requests, numpy, Pillow and fontTools; plain `python` there has none of them), so read `python`
below as `py -3.13` there; on a Mac it's `python3`. From the repo root:

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
`dist/packs/<pack>-<version>.zip` (that and its audio, for the pack server: the R2 bucket, `docs/R2_PACKS.md`) and
the pack's line in `games/catalog.json` (title, Play product id, size, checksum).

`tools/content.py` makes every clip a builder uses: Alexa's lines in the app's voice (ElevenLabs, Jessica, or Don
for Nuclear War, with the time of every word), the skill's recordings from the Mini Games CDN (speech-to-text gives
their words and times; `check=True` compares them with the words in the code, and `turns=True` splits a scene into
a line per speaker turn), beds, and pre-mixed overlaps. Everything is cached
in `tools/cache/`, so a rebuild only renders what changed. The ElevenLabs key comes from `ELEVENLABS_API_KEY` or
`all-minigames-sites/alexa/.env` and is never printed.

**The apps' own sounds and help** (`content/app/`, bundled by both apps): `tools/app_audio.py` makes the intro sting
and the listening sounds (auditions first, then the owner's pick, kept in `tools/app_audio_picks.json`) and has
Jessica read the help topics in `tools/app_text.toml`; `py -3.13 tools/app_audio.py check` says whether
`content/app/app.json` still matches them.

**The stores and the usage data.** Each tool's `--help` has its options; `docs/RELEASE.md` runs them in order.

```
py -3.13 tools/make_art.py check            # the icons, Play's feature graphic and the website's images, cut from the
                                            #   picked art (OpenAI's image models, cached in tools/cache/art/;
                                            #   docs/STORE_ART.md), and the framed screenshots
py -3.13 tools/store_shots.py android       # raw store screenshots on the emulator: phone, 7- and 10-inch tablets
                                            #   (brand/scenes.json; --targets wear --wear <serial> for a Wear OS one)
py -3.13 tools/make_art.py shots android --sizes phone,7in,10in,10in-land --replace
                                            # framed under their captions (brand/shots.json) into android/fastlane/
py -3.13 tools/make_preview.py plan         # the preview video: takes recorded on the emulator (or the Mac's
                                            #   simulator), the real sound, captions, cut to each store's rules
py -3.13 tools/check_store.py               # both listings, offline, as the fastlane check lanes check them
py -3.13 tools/check_packs.py               # the packs on R2 against games/catalog.json (--sha downloads them)
py -3.13 tools/analytics_report.py --sql    # the usage-data reports (web/analytics/views.sql); run under
                                            #   `railway run --service Postgres` to print them from the database
```

The iPhone and iPad screenshots are taken on the Mac (`StoreScreenshotsUITests`, `docs/IOS.md`) and framed with
`python3 tools/make_art.py shots ios --sizes 6.9,6.3,13 --replace` (`--replace` takes the old set out of the folder
fastlane uploads).

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

## The Android app

```
cd android
gradlew :app:assembleDebug        # app/build/outputs/apk/debug/app-debug.apk (about 190 MB with eight games)
gradlew :app:assembleRelease      # app/build/outputs/apk/release/app-release.apk (about 165 MB: R8 shrinks the code,
                                  #   and the audio is most of it; signed with the debug key, so for testing only:
                                  #   fastlane signs the store's builds)
adb install -r app/build/outputs/apk/release/app-release.apk
gradlew :app:testDebugUnitTest    # the app's JVM tests
gradlew :app:connectedDebugAndroidTest   # its screen tests on the emulator (about 200, with accessibility checks, in
                                         #   each theme, at 200% text and tablet sizes; 25 to 30 minutes)
gradlew :wear:assembleDebug       # the Wear OS app: wear/build/outputs/apk/debug/wear-debug.apk
gradlew :wear:link:test :wear:testDebugUnitTest   # its tests: the phone-watch link, and its screen under Robolectric
```

The games, their audio and their covers ship inside the app. The build takes `games/` and `content/` as assets, so
run the content tools first. The app needs Android 7 (API 24) or later, the Wear OS app Wear OS 3 (API 30) or later.
`docs/DESIGN.md` is the whole design (both apps follow it); in short:

- **Tabs:** Games, Shop, Help and Settings, after an intro with the "Epic Audio Games" sting (once per launch, and
  off in Settings) and, the first time, a short welcome. Dark, light and high-contrast themes, Atkinson Hyperlegible
  text in three sizes on top of the phone's, and everything named the same for TalkBack as on screen.
- **Games:** each game's cover, description and what's free, "In progress" on games left part-way, and a button for
  its packs.
- **Game screen:** the talking circle (the game's picture: it pulses while the game speaks, rings while it
  listens, and a tap skips). The transcript appears line by line as it is spoken, with the word being spoken
  highlighted; a line that carries on a sentence (the speaker's line before it ends with a comma or is marked to
  carry on, as in a list of names read one clip per name) joins that bubble. The answers: the mic or typing, or a
  tap on one of the question's options, shown as buttons at the end of the chat. Answers work while the voice is
  still talking, and stop it.
- **Listening:** after each question the mic opens by itself, as on Alexa, with a short sound, except with a screen
  reader on (Settings, Microphone, says when). Silence plays the question again; a second silence, or "stop",
  pauses the game until a tap. Settings also has the voice's speed, the music's volume and the time to answer.
  Google's recogniser plays sounds of its own as notification sounds, so the app mutes those while it listens and
  gives them back a moment after (`RecognizerBeep.kt`).
- **Help:** topics to read, or to hear in Jessica's voice. **Usage data:** the app sends us which screens and games
  are used, under a random ID, to our own server (see below); never what the player says, nor anything about
  accessibility. It's on by default, with a switch and "Delete my usage data" in Settings.
- **Screen off, phone in a pocket:** while a game is open it keeps talking and listening (a foreground service,
  with a notification showing the game and its cover). The headphones' button (play/pause) does what a tap on the
  talking circle does: skip, talk, stop listening, or carry on. Pause (the lock screen's, or earbuds taken out)
  pauses the game; play carries on, or talks when it's your turn. With a Bluetooth headset, the
  game listens through the headset's mic. Calls, other apps taking the audio and headphones coming out still pause.
- **Saves:** each game's place is saved at every question, and "Welcome back!" picks it up.
- **Packs:** the Shop tab has every pack; a game's card, its menu and a locked chapter end open the same rows for that
  game in a sheet: each pack's price (Google Play Billing), buying it, then downloading it from the pack server (the
  R2 bucket, `epicPacksUrl` in `android/gradle.properties`; see below), checking it against the catalog and
  unpacking it into the app's files. Purchases made before are restored the same way. Debug builds also install any
  `<pack>-<version>.zip` pushed to `/sdcard/Android/data/com.epicaudiogames.app/files/incoming/`, to try packs
  without the store or a server.
- **Tablets, foldables and Chromebooks:** from 600 dp wide a navigation rail takes the tab bar's place. From 840 dp
  the Games tab is a grid and Help shows its list beside a topic, and a game has two panes (its controls beside the
  transcript), as it also does from 600 dp sideways. Large screens turn any way and take any window size; phones
  stay upright. A keyboard has Space for the one button, Escape to pause and Ctrl+1 to 4 for the tabs.
- **Watches:** a watch's own media controls already work, through the game's media session. The Wear OS app
  (`android/wear`) shows the open game's title and state, its one button and Pause, and buzzes as the mic opens and
  closes; the phone's side is `WearBridge.kt`, through Google Play services' Data Layer (`docs/WEAR_OS.md`).

Emulator: the `EpicAudioGames_Pixel` AVD (Android 15, 6 GB of storage) was made for this app. The other AVDs on this
machine are full of other apps' builds. There's no Wear OS emulator yet: `docs/WEAR_OS.md` says how to make one.

## The iPhone and iPad app

`ios/` (`docs/IOS.md`: building with Xcode 26, the launch arguments, iPad, Mac and Vision, and what needs a real
iPhone). The same screens and words as the Android app. On the Mac:

```
swift test --package-path ios/EpicEngine                         # the Swift engine against the Kotlin fixtures, and
                                                                 #   the app's core (the watch link among it)
python3 ios/scripts/placeholder_content.py                       # once, if there's no real content/ (quiet audio)
EPIC_CONTENT_DIR=build/placeholder-content xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -derivedDataPath ios/build test
```

The last is the app's unit and UI tests, Apple's accessibility audit among them, on an iPhone and an iPad. The iPad
app turns any way and takes any window size, and runs on Apple-silicon Macs and Apple Vision Pro as "Designed for
iPad". The Apple Watch app (`ios/EpicWatch/`) is the Wear OS app's twin, through WatchConnectivity; its Xcode target
is added once, on the Mac (`docs/WATCH.md`).

## The website, the usage-data API and the packs

`web/` is epicaudiogames.com: the pages in `public/` (the home page, support, the privacy policy and the
accessibility statement, with the covers and the social preview image), served by `server.js`. The same server takes
the apps' usage data: `POST /api/events` (a batch of events, checked against the whitelist
`web/analytics/events.json`, which both apps' tests read too) and `POST /api/forget` (deletes an install's data, for
Settings' "Delete my usage data"); the top of `server.js` says what each answers. The events go to a Postgres
database (`DATABASE_URL`). Without one the site works as ever and `/api` answers 503, so the apps keep their events
and send them later. `web/analytics/views.sql` has the reports, which `tools/analytics_report.py` prints. It all
lives in the `epicaudiogames.com` project on Railway: the `web` service, and a `Postgres` service beside it.

```
npm install --prefix web                               # pg, the server's one dependency (web/node_modules/ isn't in git)
npm test --prefix web                                  # the whitelist, the API, the pages and the database code (with
                                                       #   TEST_DATABASE_URL, also against a real, scratch Postgres)
node web/server.js                                     # http://localhost:3000 (PORT to change it)
railway up web --path-as-root --service web            # deploy; `railway link` first on a new machine
node web/scripts/smoke.js https://epicaudiogames.com   # after a deploy: the API answers as it should
railway run --service Postgres py -3.13 tools/analytics_report.py   # the reports (pip install "psycopg[binary]")
```

`CANONICAL_HOST=epicaudiogames.com` on the service makes `www.` redirect to the bare domain, and
`DATABASE_URL=${{Postgres.DATABASE_URL}}` gives it the database (`docs/RELEASE.md` has the one-time setup).

**The packs** aren't on Railway, and the server no longer has a route for them (`railway up` turns the 174 MB of zips
away anyway): they're in an R2 bucket on Cloudflare,
`https://packs.epicaudiogames.com/<pack>-<version>.zip` (`docs/R2_PACKS.md`), with ranges (a broken-off download
carries on) and a year's caching. Both apps are built with that address: Android's `epicPacksUrl` in
`android/gradle.properties`, iOS's `EPIC_PACKS_URL` in `ios/Config/Base.xcconfig`. A value in
`~/.gradle/gradle.properties`, in `ORG_GRADLE_PROJECT_epicPacksUrl` or in `ios/Config/Local.xcconfig` wins over
those, so the fastlane lanes refuse a store build that doesn't use R2. The apps install a zip only if its size and
SHA-256 are the ones in the `games/catalog.json` they were built with, so a published zip is never replaced: a
changed pack is a new version (`make_pack.py --version 2`), and the old zip stays for the builds that still ask for
it. `py -3.13 tools/check_packs.py` checks the bucket against the catalog (`--sha` downloads every zip).

To try a pack without the store or R2, give a Debug build its zip: Android's `incoming/` folder (above), or the
iPhone app's `Documents/incoming/`.

## Phases

1. The map format, the engine, and the three radio plays: King of Frootopia (story 1), Noodle Rush and Signal
   Decoders. **Done.**
2. The Android app: the game list, the game screen, audio, speech, transcripts and answer buttons. **Running:** on
   Google Play's internal testing track since 7 October 2026 (versionCode 2, 1.0; `android/fastlane/README.md`);
   versionCode 3 is phase 7. Speech still to be tried on more phones.
3. The ElevenLabs voice (Jessica), and Pirate Quest, Leaning Tower of Pizza, Alien Customs (levels 1 to 5) and
   The Werewolf (stories 1 to 5). **Done.**
4. Packs and purchases (Google Play Billing, StoreKit 2). **Running:** the pack format, both apps' store and
   downloads, and the three packs, on R2 since 7 October 2026 (`docs/R2_PACKS.md`): Alien Customs levels 6 to 15
   (26 MB), The Werewolf stories 6 to 50 (133 MB) and The Kingdom of Frootopia stories 2 to 5 (15 MB). The products
   are in App Store Connect; `fastlane android iaps` makes Google Play's. Still to come: buying each pack with a
   test account on both stores.
5. Nuclear War, a size pass, and the release build. **Running:** Nuclear War is done (the whole game, in Don's
   voice; see above), and fastlane builds, signs and uploads the release build. Still to come: the size pass.
6. The iPhone app (`docs/IOS.md`). **Running:** every game, speech, saves, packs (StoreKit 2) and VoiceOver work in
   the simulator, and the Swift engine replays the Kotlin one exactly. A bug hunt on both apps fixed 99 bugs in
   both. Still to come: trying it on a phone with the real audio, and the release (`fastlane ios beta` puts a build
   on TestFlight).
7. Blind and partially sighted players first (`docs/DESIGN.md`), in both apps: tabs, the Shop, Help and Settings,
   themes and text sizes, the intro sting and listening sounds, spoken help, voice speed, first-party usage data,
   new store art and listings. **Built**, with the Android app tested on the emulator and the iPhone app's Swift
   compiled and unit-tested without Xcode. Next: TestFlight and Play's internal testing (`docs/RELEASE.md`). Before
   the listings claim VoiceOver or TalkBack: the checks on real phones at the end of `docs/DESIGN.md`. Sign-in comes
   after.
8. More devices (`docs/DESIGN.md`, Tablets and Watches): tablets, foldables and Chromebooks; iPad, and Macs and
   Vision Pro as "Designed for iPad"; the Wear OS and Apple Watch apps. **Built**: the large-screen layouts in both
   apps, with Play's 7- and 10-inch tablet screenshots; the Wear OS app, tested under Robolectric; the Apple Watch
   app's code. Still to come: the Apple Watch target in Xcode, a Wear OS emulator for Play's watch screenshots, the
   iPad and watch screenshots for the App Store, and the checks on real watches before the listings mention them.
