# The iOS app

`ios/` is the iPhone version of the app, written in Swift: the same eight games, the same maps and audio, the same
saves and packs. Both apps read `games/` and `content/`. The Swift engine is a port of the Kotlin one and is checked
against it: `fixtures/engine/` holds what the Kotlin engine does, and the Swift tests replay it exactly
(`docs/IOS_PARITY.md`).

| Folder | What's in it |
|---|---|
| `ios/EpicEngine/` | a Swift package: `EpicEngine` (maps, answers, saves, Nuclear War), `EpicAppCore` (the app's logic that needs no UI: catalog, saves, transcript timing, packs), `EpicConformance` (replays the Kotlin fixtures) and `eag` (play a game by typing) |
| `ios/EpicAudioGames/` | the SwiftUI app: `Game/` (the game loop), `Audio/` (gapless playback), `Speech/`, `Store/` (StoreKit 2 and pack downloads), `UI/`, `Accessibility/` |
| `ios/EpicAudioGames.xcodeproj` | the Xcode project (iPhone, iOS 17 or later, bundle id `com.epicaudiogames.app`) |
| `ios/Config/` | build settings; `Local.xcconfig` (not in git) holds this machine's team and pack server |
| `ios/scripts/` | `bundle_content.sh` (copies `games/` and `content/` into the app), `placeholder_content.py`, `render_icon.swift` |

## Running it

Needs Xcode 16 or later. From the repo root:

```
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # then check DEVELOPMENT_TEAM and EPIC_PACKS_URL
open ios/EpicAudioGames.xcodeproj                                # pick an iPhone and Run
```

The build copies `content/` into the app, so build the content first (README) or put a built `content/` in the repo
root. Without it, a Debug build still runs but has no audio, and a Release build fails.

Without the real audio, make placeholder audio (quiet tones of the right lengths, and plain covers) and build with
it:

```
python3 ios/scripts/placeholder_content.py         # -> build/placeholder-content/ and build/placeholder-packs/
EPIC_CONTENT_DIR=build/placeholder-content xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ios/build build
```

`EPIC_CONTENT_GAMES="noodle-rush nuclear-war"` bundles only those games, for a quicker Debug build.

On the Android side, `-PepicContentDir=<dir>` does the same, with an absolute path: `cd android && sh ./gradlew
:app:assembleDebug -PepicContentDir=$PWD/../build/placeholder-content`.

## Testing

```
swift test --package-path ios/EpicEngine                         # the engine, app core and Kotlin fixtures (~1 min)
EPIC_SLOW=1 swift test -c release --package-path ios/EpicEngine  # with full counts: 3,000 Nuclear War games, every map walk
EPIC_CONTENT_DIR=build/placeholder-content xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ios/build test   # the app: unit and UI tests
swift run --package-path ios/EpicEngine eag noodle-rush          # play a game by typing (nuclear-war too)
```

The UI tests play games through (buttons, typing, ends, leaving and coming back), replay the fixed bugs, and run
Apple's accessibility audit. Purchases are tested with `ios/Config/EpicAudioGames.storekit` (Xcode: Debug ›
StoreKit › Manage Transactions); a debug build also installs any `<pack>-<version>.zip` dropped into the app's
`Documents/incoming/`.

After changing the Kotlin engine, a map or a pack, regenerate the fixtures and check the Swift engine still matches:

```
cd android && sh ./gradlew :engine:goldens && cd .. && swift test --package-path ios/EpicEngine
```

## What needs a real iPhone

The simulator has no microphone and no real audio route. On a phone, with the real `content/`:

- **Speech:** play Noodle Rush and Signal Decoders by voice only. Silence replays the question, a second silence
  (or "stop") pauses; mumbling gets the game's "didn't catch that" answer; refusing the mic leaves typing and the
  chips working.
- **Audio:** lines highlight in time with the voice on the speaker and on AirPods; Don's sentences in Nuclear War
  and the Leaning Tower of Pizza music have no gaps.
- **Interruptions:** a phone call, Siri, an alarm, pulling out headphones. Each should end in "Tap to carry on", with
  the mic still working after (also when it happened with the phone locked: carry on with the headphones' button).
- **The phone locked** (`UIBackgroundModes` audio): lock the phone mid-turn and put it in a pocket. The voice plays
  on; the game then listens by itself, and answering out loud through the headphones carries on, turn after turn
  (the orange/red recording dot stays on while a game is open with the mic allowed: the mic is kept running so iOS
  lets it listen in the background). Check a silence and "stop" while locked, and that a game paused or at its end
  plays nothing. Also try connecting AirPods while locked mid-game (the mic restarts on the new input), and a call
  while locked, then carrying on.
- **AirPods' mic:** with AirPods in, the game hears you through them, not the iPhone (put the phone away from you).
  On iOS 26 with recent AirPods (high-quality Bluetooth recording) the voice stays full quality; on older iOS or
  other headsets the voice drops to call quality for as long as the game is open (Bluetooth's hands-free profile is
  the only one with a mic). A wired headset's mic is used likewise.
- **The headphones' button and the lock screen:** Now Playing shows the game's title, "Epic Audio Games" and its
  cover, "playing" while it speaks or listens. The one-button play/pause (an AirPods press, a wired headset's
  click) does what Magic Tap does: skips the voice, starts or stops listening while it waits, carries on after a
  pause. Pause on its own (taking an AirPod out, the lock screen while the game talks) pauses the game; play on its
  own carries on after a pause, or starts listening while it waits. Next/previous and seeking are off. Leaving the
  game clears it.
- **Packs:** buy a pack in a TestFlight (sandbox) build, download it, and carry on at NEXT CHAPTER; Restore after
  reinstalling. Needs the pack server (`EPIC_PACKS_URL = https:/$()/epicaudiogames.com/packs`, with the zips on it:
  README, "The website") and the products in App Store Connect.
- **VoiceOver:** play Noodle Rush with VoiceOver and the screen curtain on: Magic Tap skips, talks or carries on;
  the mic doesn't open by itself; the pause is modal.
- **iOS 17:** Nuclear War's voice clips are Ogg Opus. iOS 26 plays them; iOS 17 hasn't been tried.

## Before the App Store

- Products in App Store Connect with the catalog's ids (`frootopia_stories`, `alien_customs_levels`,
  `the_werewolf_stories`), and the Paid Apps agreement.
- The pack server live at `https://epicaudiogames.com/packs` (README, "The website"): the zips from `dist/packs/`
  on the web service's volume, with exactly the sizes and SHA-256s in `games/catalog.json` (the same zips as
  Android; both apps refuse any other bytes). `EPIC_PACKS_URL` is set in `Local.xcconfig` on the Mac that builds
  for TestFlight: without it a build hides buying packs.
- The size: about 190 MB of audio is near the 200 MB limit for cellular downloads; check the App Thinning report.
- Store listing, privacy labels (speech is recognised by Apple, on the device where it can be), the age rating
  (Nuclear War) and screenshots.
