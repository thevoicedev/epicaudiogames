# iOS parity ledger

The iOS app (`ios/`) is a Swift port of the Android app and its Kotlin engine. The Kotlin engine is the reference.
`fixtures/engine/` holds what it does: written by `android/engine/src/test/.../golden/` and replayed by the Swift
tests in `ios/EpicEngine/Tests/EpicConformanceTests/`. Every place where iOS deliberately behaves differently is
listed here, with its reason and the test that pins it.

## Keeping the two engines together

After any change to the Kotlin engine, a map or a pack:

```
cd android && sh ./gradlew :engine:goldens        # rewrites fixtures/engine/; commit it
cd ../ios/EpicEngine && swift test                 # the Swift engine must still replay it
```

The Swift tests check the fixtures' header hashes of `games/` and the Kotlin sources, and fail with
"fixtures stale" when they're out of date. `:engine:goldensCheck` fails when the fixtures aren't what the
Kotlin engine makes now.

## Both apps: answering in a chat

The games are a chat, in both apps alike. Saying or typing is the main way to answer; the bar under the transcript
has only the text box, Send and the mic. While a question is asked and has options (`Ask.buttons`), they show as small
quick-reply chips at the end of the transcript, under its last line, inside what scrolls:

- **Look:** a pill (fully rounded), 36 dp/pt tall, 14 dp/pt either side of its label, Lilita One at 15 sp/pt, the
  label as written (not uppercased), centred, in ink on white, edged 2 dp/pt in the reply bubble's colour (`FFF3C4`),
  at least 48 dp/pt wide.
- **Layout:** left to right, 8 apart, a new line when the next chip doesn't fit. A chip is as wide as its label and
  a word is never broken; a label wider than a line takes the line and wraps between words. There's no cap on their
  number (the most any question has is 5).
- **Tapping one** sends its value, as the buttons did, and the reply shows its label (B011). A tap within 500 ms of a
  new question is the last tap's double and is let go (B032).
- **When:** they appear as the question's turn starts, as the buttons did (an answer may cut the voice short), and
  they belong to that question only: answered (by a chip, by voice or typed) or moved on from, they go, and the next
  question's come. Ends keep their panel (PLAY AGAIN, NEXT CHAPTER, BACK TO GAMES, GET …): those aren't answers.
- **Scrolling:** the transcript scrolls to its end when an entry comes or grows, when the chips come, when it has
  less room (the keyboard, the end panel), and when the keyboard goes (on iOS once the drag that put it away is
  over), so the newest line and the chips stay in view.
- **Accessibility:** each chip is a button named by its label; the group is "Options" (TalkBack: a heading and a
  collection; VoiceOver: a container). Each is at least 48 dp (Android) or 44 pt (iOS) to touch, the space above and
  below it counting, so the lines of chips are 12 dp (Android) or 8 pt (iOS) apart to the eye.
- **The Werewolf's accusation** (`ga`) offers only "List villagers", which reads the villagers in the chat; the
  player says or types a name. (B008's nine villager buttons were taken out again: tapping isn't meant to be the only
  way to play.)

## Deliberate differences

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| L2 | A call, Siri or an alarm, the turn's or the mic's engine stopping itself while in use, the media services restarting, and a turn whose audio can't start at all (a call has it) all pause the game: "Tap to carry on", also at an end or while idle. The session's events are reported even when it couldn't be made active as the game opened | A passing loss of audio focus pauses the voice and resumes it by itself; a lasting loss, focus refused, or headphones taken out pause the game (B031, B039) | iOS stops the engine and doesn't restart it, so the turn would never finish | TurnPlayerTests (`aTurnThatCantStartStalls`, `eventsAreReportedEvenIfTheSessionCantBeActive`), GameControllerTests (`aTurnWhoseAudioCantPlayWaitsForATap`); on a device, the plan's interruption matrix |
| L22 | The mic is kept running (an input-only AVAudioEngine, `MicInput`) from when a game opens with the mic allowed until it closes; between answers its sound goes nowhere, and each answer is a new recognition request on it. Leaving the app or locking the phone doesn't pause the game | The recogniser opens the mic for each answer; a foreground service keeps the game going with the screen off (`BackgroundPlay.kt`) | iOS refuses to start recording in the background (`cannotStartRecording`), so a mic opened per answer could never listen with the phone locked | BackgroundAudioTests, AppModelTests (`theGamePlaysOnInTheBackground`), PlaythroughUITests (`testTheGamePlaysOnInTheBackground`); on a device, the phone locked |
| L23 | The lock screen's Now Playing (the game, its cover; playing while it speaks or listens). The headphones' one button (togglePlayPause) does what Magic Tap does: carry on after a pause, skip the voice, start or stop listening. Pause on its own (an AirPod taken out) pauses the game; play on its own carries on, or starts listening while the game waits | The notification and media session's button do what a tap on the talking circle does (`BackgroundPlay.kt`) | The platform's own controls; Magic Tap is iOS's one-button action | GameControllerTests (`theHeadphonesButtonDoesWhatMagicTapDoes`, `pauseAndPlayFromTheHeadphones`, `theLockScreenShowsTheGameWhileItsOpen`) |
| L7 | The ⋮ menu is iOS's `Menu`, anchored to its button | Material's `DropdownMenu`, dropping from the ⋮ | The platform's own control | Screenshot review |
| L9 | Nuclear War's missing clips are tracked per game (`NuclearWar.missing`) | One set on the shared `NuclearAudio` | `NuclearAudio` is immutable and shared between games | NuclearWarTests |
| L12 | The JSON reader refuses unquoted literals (`00`, `tru`); otherwise it takes what kotlinx 1.6.3 takes | kotlinx reads unquoted literals | No map or save has them; refusing them keeps the reader small | JSONTests, TextConf |
| L13 | A refunded or revoked pack is taken off the phone, once its game is closed (D11) | A refunded pack stays | The App Store revokes a refunded purchase; deleting a pack under a game playing it would break the game | StoreTests (`aRefundTakesThePackAwayOnceItsGameCloses`) |
| L15 | Speech is SFSpeechRecognizer in the player's first English (else US English), on the device where it can be and on Apple's servers where not (D9). The app decides when an answer is over: no words for 6 s is a silence, words unchanged for 1.2 s are the answer, 20 s at most. Its errors are read as Android reads its own, but trouble after an interruption or a route change never turns the mic off | SpeechRecognizer (free form, offline preferred, 5 guesses), which decides when speech has ended | iOS's recogniser listens until told to stop, and usually gives one guess where Android gives five | EndpointerTests, SpeechTests; the timings need tuning on a device |
| L16 | Opening a game asks for the mic and for speech recognition (both are needed to listen). After "Don't Allow", iOS never asks again: the mic button says the mic is off and leads to Settings | The first game opened asks for the mic; the mic button asks again while Android still will, then says the mic is off and leads to Settings (B015, B080) | iOS asks for each permission once | PlaythroughUITests (`testTheMicIsAskedForAsAGameOpens`), BugReplayUITests (`testB015TheMicOffLeadsToSettings`) |
| L17 | While paused, the dimmed back arrow leaves the game | The pause takes that tap too (carrying on); the system Back button leaves | iOS has no system Back | PlaythroughUITests (`testNoodleRushByVoice`) |
| L18 | The keyboard stays up after sending, as on Android, and dragging the transcript down into it puts it away | The system Back button puts it away | An iPhone keyboard has no key to hide it | PlaythroughUITests (`testNoodleRushToAnEndingAndBack`) |
| L19 | A pack's zip must be stored, not compressed: a compressed or encrypted entry is refused | `ZipInputStream` inflates compressed entries | `tools/make_pack.py` writes stored entries (the audio doesn't compress), and a reader of stored zips is small | PackStoreTests (`compressedAndBrokenZipsAreRefused`) |
| L20 | "Restore purchases" asks the App Store again (`AppStore.sync`, which may ask the player to sign in); opening the sheet only reads the purchases again | Both read Play's purchases | Apple asks apps to sync only when the player asks | StoreTests (`aFailedDownloadIsTriedAgainLater`) |
| L21 | A card, the mic, a chip, the packs pill and "Restore purchases" darken by 10% while pressed | Compose's ripple: a circle spreading from the finger, the same 10% | SwiftUI has no ripple; the pressed shade is the same | Screenshot review |
| A1 | With VoiceOver on, the game doesn't open the mic by itself after a question (it would hear VoiceOver); the player opens it with Magic Tap or the mic, and a short system sound says it's listening (D8) | It listens by itself, TalkBack or not | VoiceOver reading the screen would be heard as an answer | GameControllerTests (`withVoiceOverTheGameWaitsForThePlayerToTalk`); on a device with VoiceOver |
| A2 | VoiceOver gestures: Magic Tap skips the voice, carries on after a pause, or starts and stops listening; Escape (the two-finger scrub) leaves the game | TalkBack has no Magic Tap; Back leaves | The platform's own gestures | On a device with VoiceOver |
| A3 | The talking circle is named "Skip" while the game speaks, "Stop listening" while it listens, else "Talk"; a game line reads as one element, its speaker first ("Gribbo: …"), and a reply as "You said: …" | The circle is "Skip" or "Talk"; lines and replies read as their text | VoiceOver's plan (Phase 8); an Android candidate | BugReplayUITests (`testB063TypingStopsTheMic`), PlaythroughUITests |
| A4 | The header, the talking circle, and the end panel's and store sheet's outlined titles stop growing at the second accessibility text size (`accessibility2`); the rest grows all the way | Every text grows with the font scale (Android's largest is 200%, about iOS's `accessibility2`) | The plan's Phase 8: the transcript keeps some room at the largest sizes, and "CHAPTER COMPLETE!" isn't cut short | AccessibilityAuditTests (let through as "capped at accessibility2"), BugReplayUITests (`testB076PanelsScrollWithTheLargestText`) |
| A5 | Reduce Motion stops the circle's pulse (its gold ring still shows the game speaking) | No check of its own: the pulse is left to the system's animation settings | The plan's Phase 8 | Screenshot review |

Numbers no longer listed (L1, L3, L4, L5, L6, L8, L11, L14) were differences that the bug fixes removed: both apps
now do what the iOS column said (an engine error is a note and back to the list; a second listen does nothing; a
turn's first beds start once; a missing or broken clip is passed over; no sale without a pack server; the loading
overlay takes the touches; a save that can't be opened starts the game afresh; a pack installed while its own game
waits at the end it unlocks opens the game there with NEXT CHAPTER). Code comments still cite them for that
behaviour.

### The accessibility audit

`EpicAudioGamesUITests/AccessibilityAuditTests.swift` runs `performAccessibilityAudit()` on the game list, a game
asking a question (Noodle Rush, its chips showing), an end panel and the store sheet. What it lets through, and why:

- **Contrast**, for transcript lines scrolled out of the transcript's view: the audit measures what's drawn over them
  there (the picture, the backdrop). Where they show, they're ink on white or cream.
- **Contrast**, for the store sheet's outlined title: gold letters ringed in ink; the audit reads the gold alone.
- **Dynamic Type**, for the game's title, the circle's status and the outlined titles of the end panel and the store
  sheet: capped at `accessibility2` (A4).
- **Text clipped**, for the text box: it's one line, and what's typed scrolls sideways in it; it grows with the text
  size.
- **Text clipped**, for the store sheet's rows: the sheet is as tall as what's in it, up to the screen; with the
  largest text its rows go past its foot and it scrolls to them.
- **Element detection**, on the store sheet with no element named: the list's text showing around the sheet (iOS 26
  floats it), which VoiceOver rightly doesn't reach while the sheet is up.

## Decisions taken in the port

- **Regular expressions.** Maps' `re` answers and the negation check use ICU (`NSRegularExpression`), not a port of
  `java.util.regex`. The two engines differ only on POSIX and Unicode classes, class set operations, inline flags
  and a few newer escapes. No map uses them, and `MapRegexTests` fails if one ever does. The answers they run on are
  normalised to `[a-z0-9' ]` first.
- **Text comparison.** Variable names, node ids, `by` cases, symbol tables and pack merges compare UTF-16 units
  exactly, as Kotlin's `String.equals` does. Swift's `==` treats canonically equal strings (é precomposed and
  decomposed) as equal, which Kotlin doesn't.
- **Doubles as text.** `Kt.doubleString` is a port of JDK 17's `Double.toString`, including its non-shortest
  digits (1e23 prints as `9.999999999999999E22`).
- **Random numbers.** Both engines draw from Kotlin's XorWow (`XorWowRandom` in Swift is bit-exact), with the same
  calls in the same order, so a seed plays the same game on both.
- **Deep maps.** Session's `go` hops run as a loop rather than recursion, so a looping map reaches Kotlin's 500-hop
  error instead of overflowing a thread stack.
- **Nuclear War's numbers wrap as Kotlin's do.** Every Kotlin `Int` field in the state (environment, round, scores,
  bombs, shields and so on) is stored through `@KotlinInt`, which keeps the low 32 bits, and balances (Kotlin
  `Long`) change with `&+` and `&-`. Swift's checked arithmetic would otherwise crash on a corrupt save, or rank an
  overflowing score differently. Pinned by NuclearRegressionTests, whose expected values came from the Kotlin engine.
- **Opening a game after an end (D15, settled in both apps).** A chapter end whose next chapter is in the map comes
  back at that end, with "Welcome back!" and NEXT CHAPTER (B001); any other end, and a plain quit, starts the game
  again keeping the map's `keep` variables, as PLAY AGAIN's `restart()` does (B002, B027): Alien Customs keeps its
  level, Leaning Tower of Pizza its best score, The Werewolf its stories played. Pinned by OpenTests and OpenPolicyTests
  on both sides, and the goldens' walks.
- **D2, product ids.** The App Store products are the catalog's Play ids (`frootopia_stories`,
  `alien_customs_levels`, `the_werewolf_stories`); a catalog `appstore` key would override one. `ios/Config/
  EpicAudioGames.storekit` has them for StoreKit testing in Xcode (the scheme's Run action uses it).
- **D13, voice processing** stays off, as on Android: the mic listens through a plain input-only engine (kept running
  while a game is open, L22).
- **Headsets' mics.** The session allows Bluetooth headsets as inputs (`.allowBluetoothHFP`, and from iOS 26
  `.bluetoothHighQualityRecording`) besides A2DP output, and prefers a headset's mic to the iPhone's
  (`AudioSessionController.preferHeadsetMic`). The cost, before iOS 26 or with headsets that can't record in high
  quality: the voice is call quality on Bluetooth headphones for as long as a game is open.
- **Nuclear War compares saved text by UTF-16 units** (`kEquals`, `kContains`), as Kotlin does, for country refs
  and city names read from a save.

## Found on Android while porting (not changed)

- `MapsTest`'s printed exploration stats move between runs: its ended-state continuations use an unseeded
  `Session(map)` (MapsTest.kt:109). The Leaning Tower of Pizza turn count was 1615322 in two runs and 1615492 in
  one. The Swift gate compares the golden bots' seeded walks instead.
- A fresh checkout couldn't run `:engine:test` when `tools/cache/parity` was missing (`inputs.dir(...).optional()`
  still checks that the folder exists); build.gradle.kts now uses a file tree.
- `android/gradlew` is committed without its execute bit: run it as `sh ./gradlew`.

## Android candidates (not applied)

The earlier list (reopening at the chapter end a new pack unlocks, `packInstalled` leaving other games alone, keeping
`keep` variables after an end, the double `listen()`, a missing clip holding a turn up, and the packs left out of Auto
Backup) is done in both apps. What's left:

- VoiceOver's D8 for TalkBack: not opening the mic by itself while TalkBack runs, with a sound when it opens (A1).
- The talking circle named "Stop listening" while it listens, and replies read "You said: …" (A3).
- `NuclearAudio.missing` shared across games (L9).
