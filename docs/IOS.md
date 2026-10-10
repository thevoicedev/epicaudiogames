# The iOS app

`ios/` is the iPhone and iPad version of the app, written in Swift: the same eight games, the same maps and audio,
the same saves and packs, and the same screens as the Android app (`docs/DESIGN.md`). Both apps read `games/` and
`content/`. The Swift engine is a port of the Kotlin one and is checked against it: `fixtures/engine/` holds what the
Kotlin engine does, and the Swift tests replay it exactly. Where the two apps differ on purpose is
`docs/IOS_PARITY.md`.

| Folder | What's in it |
|---|---|
| `ios/EpicEngine/` | a Swift package: `EpicEngine` (maps, answers, saves, Nuclear War), `EpicAppCore` (the app's logic that needs no UI: catalog, saves, transcript timing, packs, the help manifest, when an answer is over, the watch's messages), `EpicConformance` (replays the Kotlin fixtures) and `eag` (play a game by typing) |
| `ios/EpicAudioGames/` | the SwiftUI app: `App/` (the model, settings, links), `UI/` (the screens) and `UI/Design/` (tokens, type, theme, components, window sizes), `Game/` (the game loop), `Audio/` (gapless playback, the app's own sounds), `Speech/`, `Store/` (StoreKit 2 and pack downloads), `Accessibility/`, `Analytics/` (usage data), `Watch/` (the Apple Watch link), `Debug/` (launch arguments, the Audio Lab) |
| `ios/EpicWatch/` | the Apple Watch app (`docs/WATCH.md`); its target is added in Xcode on the Mac |
| `ios/EpicAudioGames.xcodeproj` | the Xcode project (iPhone and iPad, iOS 17 or later, bundle id `com.epicaudiogames.app`) |
| `ios/Config/` | build settings; `Base.xcconfig` has the pack server (R2), `App.xcconfig` the app's own (iPhone and iPad, main-actor isolation), `Local.xcconfig` (not in git) this machine's team |
| `ios/scripts/` | `bundle_content.sh` (copies `games/`, `content/` and the fonts into the app), `placeholder_content.py` |

The app's icons (`Resources/Assets.xcassets`: `AppIcon` with its dark and tinted versions, and `LaunchLogo`) are made by
`tools/make_art.py export icons` from the picked art (`docs/STORE_ART.md`), which replaced the old
`ios/scripts/render_icon.swift`.

## The app

As a player meets it (`docs/DESIGN.md` › Structure):

- **The way in:** the launch screen (navy, the emblem), then the intro (`UI/IntroView.swift`: the emblem, the
  wordmark and the sting, once per launch, skippable, not at all with Settings › Play the intro sound off), then on
  the first run onboarding (`UI/OnboardingView.swift`: welcome, the microphone, comfort, VoiceOver's page when it's on,
  you're ready), which Help and Settings can show again.
- **The tabs** (`UI/MainTabs.swift`): Games (`HomeView`), Shop (`ShopView`, the packs on `PackRows`), Help (`HelpView`:
  topics read aloud from `content/app/app.json`) and Settings (`SettingsView`, with Licences).
- **A game** (`GameView`, full screen): the header and its menu, the talking circle, the transcript (`FeedView`), the
  chips and the answer bar, the end panel, the Paused overlay, the store sheet and the help sheet.
- **Underneath:** `AppModel` (the way in, the tabs, the game, the sheets), `AppSettings` (the `settings.*` keys,
  `UserDefaults`), `AppAudio` (the sting, pages read aloud, short sounds and Settings' samples), `UsageData`
  (`Analytics/`, to our server under a random ID, off in Settings › Privacy) and `WatchBridge`.

Each Swift file names its Kotlin counterpart in its first line, and keeps the Android app's words and identifiers.

## Running it

Needs Xcode 26 (the app is Swift 6.2: code is main-actor isolated unless it says otherwise, App.xcconfig's
`SWIFT_DEFAULT_ACTOR_ISOLATION`), which App Store Connect also requires for uploads. From the repo root:

```
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # then check DEVELOPMENT_TEAM
open ios/EpicAudioGames.xcodeproj                                # pick an iPhone or an iPad and Run
```

Packs download from `EPIC_PACKS_URL` in `Base.xcconfig`, the R2 bucket `https://packs.epicaudiogames.com`
(`docs/R2_PACKS.md`). Leave it out of `Local.xcconfig`, which would win: an old copy of the example still points at
the website's retired `/packs`, and `fastlane ios beta` stops on any address but R2's.

The build copies `content/` into the app, so build the content first (README) or put a built `content/` in the repo
root. Without it, a Debug build still runs but has no audio, and a Release build fails. `content/app/` (the app's
own sounds, spoken help and the font's licence, `tools/app_audio.py`) goes in every build.

Without the real audio, make placeholder audio (quiet tones of the right lengths, and plain covers; `content/app/`
goes in as it is) and build with it:

```
python3 ios/scripts/placeholder_content.py         # -> build/placeholder-content/ and build/placeholder-packs/
EPIC_CONTENT_DIR=build/placeholder-content xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ios/build build
```

`EPIC_CONTENT_GAMES="noodle-rush nuclear-war"` bundles only those games, for a quicker Debug build.

On the Android side, `-PepicContentDir=<dir>` does the same, with an absolute path: `cd android && sh ./gradlew
:app:assembleDebug -PepicContentDir=$PWD/../build/placeholder-content`.

### Launch arguments (Debug builds)

A Debug build plays itself from its launch arguments (`Debug/DebugLaunch.swift`), for the UI tests, the store
screenshots and checks. Android's debug build takes the same names as launch extras (`DebugLaunch.kt`).

| Argument | What it does |
|---|---|
| `-EpicReset YES` | every game's save cleared, and the settings stored forgotten (the UI tests start so) |
| `-EpicNoIntro YES`, `-EpicIntro YES` | no intro this launch, or the intro even so; `-EpicHoldIntro YES` keeps it until it's skipped, silent |
| `-EpicSkipOnboarding YES`, `-EpicOnboarding YES` | no onboarding this launch, or onboarding from its first page; `-EpicVoiceOver YES` shows it as with VoiceOver on |
| `-EpicTab <games\|shop\|help\|settings>`, `-EpicHelp <topic id>` | the tab the app starts on; the Help tab on a topic (`voice`) |
| `-EpicTheme <system\|light\|dark\|contrast>`, `-EpicTextSize <1.0\|1.15\|1.3>`, `-EpicSpeed <0.75 … 2>` | those settings, stored as if picked in Settings |
| `-EpicContrast increased` | the palettes as with the phone's Increase Contrast |
| `-EpicAnalytics off`, or a server's address | no usage data this launch, or usage data to that server (`http://localhost:3000`) |
| `-EpicOpen <game id>`, `-EpicFresh YES` | opens the game (its save cleared first) |
| `-EpicSay "yes\|no"`, `-EpicSayDelay <s>`, `-EpicSkip YES`, `-EpicPauseAt <s>` | answers each question in turn (a last answer ending in `*` again and again), each that long after its question; skips each turn's voice; pauses that long after the game opens |
| `-EpicHear "~\|yes\|?"`, `-EpicMic off` | the games hear these instead of the mic (`~` a silence, `?` speech not made out), the mic counting as allowed; or no mic at all |
| `-EpicStore <game id>`, `-EpicPacksURL <url>`, `-EpicLab YES` | the game's store sheet; another pack server; the Audio Lab |
| `-settings.<key> <value>` | any setting for this launch alone (`-settings.theme contrast`) |

For example: `xcrun simctl launch booted com.epicaudiogames.app -EpicNoIntro YES -EpicSkipOnboarding YES -EpicOpen
noodle-rush -EpicSkip YES -EpicSay "yes|yes"`. The unit tests' host app shows no intro or onboarding and sends no
usage data.

### iPad, Mac and Vision

The app target is iPhone and iPad (`App.xcconfig`'s `TARGETED_DEVICE_FAMILY = 1,2`; the test targets stay iPhone
apps, `Base.xcconfig`). An iPad turns any way and takes any window size (Split View, Stage Manager): `Info.plist`
lists the four orientations and has no `UIRequiresFullScreen`; iPhones stay upright. The layouts follow the window's
width (`UI/Design/Window.swift`, `docs/DESIGN.md` › Tablets…): from 840 pt the Games tab is a grid of two columns and
a game has two panes (also from 600 pt in landscape); Help shows its list and a topic side by side on a regular width.
The tab bar is the system's (at the top on iPadOS 18 and later). A keyboard has ⌘1–4 for the tabs, Space as the one
button and Escape (the ⌘-hold overlay lists them), and every button has a hover effect.

The same app runs on Apple-silicon Macs and Apple Vision Pro as "Designed for iPad" (`App.xcconfig`): in Xcode run it
on My Mac (Designed for iPad) and on the visionOS simulator, and check the window sizes, the keyboard and the pointer.
App Store Connect needs 13-inch iPad screenshots (2064x2752) for review once the app is on iPad (below).

### The Apple Watch app

`ios/EpicWatch/` is a remote for the game on the iPhone: its title, its state in words, one big button named as the
talking circle is, Pause, and a buzz as the mic opens and another as it closes (`docs/DESIGN.md` › Watches). The
iPhone's side is `Watch/WatchBridge.swift`, the shared messages `EpicAppCore/WatchLink.swift`. The watch target is
added in Xcode on the Mac, once: `docs/WATCH.md` has the steps, the testing on a paired simulator, the screenshots
(`-EpicWatchDemo <state>`) and the checks on a real watch.

## Testing

```
swift test --package-path ios/EpicEngine                         # the engine, app core and Kotlin fixtures (~1 min)
EPIC_SLOW=1 swift test -c release --package-path ios/EpicEngine  # with full counts: 3,000 Nuclear War games, every map walk
python3 ios/scripts/placeholder_content.py                       # once, or use the real content/
EPIC_CONTENT_DIR=build/placeholder-content xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -derivedDataPath ios/build test
swift run --package-path ios/EpicEngine eag noodle-rush          # play a game by typing (nuclear-war too)
```

The unit tests cover the model, the game loop, the audio and the mic's gate, settings, the design's contrast pairs
and type, Help, usage data (against `web/analytics/events.json`), the store and the watch's link; some read the repo
(`content/app/`, `docs/DESIGN.md`, `web/analytics/`) through `EPIC_REPO_ROOT`, so commit those first. The UI tests play
games through (buttons, typing, ends, leaving and coming back), replay the fixed bugs, and walk the tabs, Help, the
intro and onboarding (`PlaythroughUITests`, `BugReplayUITests`, `TabsUITests`, `HelpUITests`,
`IntroOnboardingUITests`); `AccessibilityAuditTests` runs Apple's accessibility audit over every screen in each of the
design's looks, and on an iPad its grid and two-pane game (`docs/IOS_PARITY.md` lists what it lets through, and why).
Each UI test launches with `-EpicReset YES -EpicNoIntro YES -EpicSkipOnboarding YES -EpicAnalytics off`. Purchases are
tested with `ios/Config/EpicAudioGames.storekit` (Xcode: Debug › StoreKit › Manage Transactions); a debug build also
installs any `<pack>-<version>.zip` dropped into the app's `Documents/incoming/`.

**Store screenshots** are `StoreScreenshotsUITests`, skipped unless `TEST_RUNNER_EPIC_STORE_SHOTS` names a folder: the
same scenes as Android's (`brand/scenes.json`, `brand/shots.json`), on an iPhone 17 Pro Max (6.9") and an iPad Pro
13-inch (M4), raw into `build/store-shots/ios/raw/` (the iPad's into `ipad13/`), with the Shop's in-app purchase shots
(`iap_<product id>.png`); then `python3 tools/make_art.py shots ios --sizes 6.9,6.3,13` frames them. The simulator's
setup (English, the status bar at 9:41) and the commands are at the top of the test and in `docs/RELEASE.md`.

After changing the Kotlin engine, a map or a pack, regenerate the fixtures and check the Swift engine still matches:

```
cd android && sh ./gradlew :engine:goldens && cd .. && swift test --package-path ios/EpicEngine
```

## What needs a real iPhone

The simulator has no microphone and no real audio route. On a phone, with the real `content/`:

- **Speech:** play Noodle Rush and Signal Decoders by voice only. Each listen starts with the listening sound, and the
  sound is never heard as an answer; silence replays the question, a second silence (or "stop") pauses; mumbling gets
  the game's "didn't catch that" answer; refusing the mic leaves typing and the chips working. Try Settings › Time to
  answer at Longest.
- **Audio:** lines highlight in time with the voice on the speaker and on AirPods, at every voice speed from 0.75 to
  2×; Don's sentences in Nuclear War and the Leaning Tower of Pizza music have no gaps; the intro's sting, with the
  silent switch on (quiet) and with music playing in another app (none).
- **Interruptions:** a phone call, Siri, an alarm, pulling out headphones. Each should end paused ("Carry on"), with
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
- **Packs:** buy a pack in a TestFlight (sandbox) build from the Shop tab, download it, and carry on at "Next
  chapter"; Restore after reinstalling. The zips are on R2 (`python3 tools/check_packs.py --sha` checks them against
  the catalog), and the products in App Store Connect.
- **VoiceOver:** play Noodle Rush with VoiceOver and the screen curtain on: Magic Tap skips, talks or carries on;
  the mic doesn't open by itself; the pause is modal; the focus lands on the end panel's and the pause's headings.
- **iPad:** the same on an iPad, turned both ways and in Split View, with a hardware keyboard.
- **iOS 17:** Nuclear War's voice clips are Ogg Opus. iOS 26 plays them; iOS 17 hasn't been tried.

The whole device checklist, for both apps, is at the end of `docs/DESIGN.md` (Checking on real phones): the listing
claims VoiceOver only once it passes. The watch's is in `docs/WATCH.md`.

## Before the App Store

- Products in App Store Connect with the catalog's ids (`frootopia_stories`, `alien_customs_levels`,
  `the_werewolf_stories`), and the Paid Apps agreement.
- The packs on R2 (`https://packs.epicaudiogames.com`, `docs/R2_PACKS.md`), with exactly the sizes and SHA-256s in
  `games/catalog.json` (the same zips as Android; both apps refuse any other bytes). `Base.xcconfig` has the address;
  `fastlane ios beta` stops if a `Local.xcconfig` points the build anywhere else.
- The size: about 190 MB of audio is near the 200 MB limit for cellular downloads; check the App Thinning report.
- The listing, the App Privacy answers (usage data, and speech recognised by Apple, on the device where it can be),
  the age rating (Nuclear War), the screenshots (6.9" and 6.3" iPhone, 13" iPad, and Apple Watch once the watch app
  ships) and the App Preview: `ios/fastlane/README.md`, `docs/STORE_LISTING.md`, `docs/STORE_ART.md`, and
  `docs/RELEASE.md` for the order.
