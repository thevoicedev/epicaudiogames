# iOS parity ledger

The iOS app (`ios/`) is a Swift port of the Android app and its Kotlin engine. The Kotlin engine is the reference.
`fixtures/engine/` holds what it does: written by `android/engine/src/test/.../golden/` and replayed by the Swift
tests in `ios/EpicEngine/Tests/EpicConformanceTests/`. Both apps' screens, words, colours and screen-reader behaviour
follow `docs/DESIGN.md`. Every place where iOS deliberately behaves differently is listed here, with its reason and the
test that pins it.

## Keeping the two engines together

After any change to the Kotlin engine, a map or a pack:

```
cd android && sh ./gradlew :engine:goldens        # rewrites fixtures/engine/; commit it
cd ../ios/EpicEngine && swift test                 # the Swift engine must still replay it
```

The Swift tests check the fixtures' header hashes of `games/` and the Kotlin sources, and fail with
"fixtures stale" when they're out of date. `:engine:goldensCheck` fails when the fixtures aren't what the
Kotlin engine makes now.

## Keeping the two apps together

Each Swift file names its Kotlin counterpart in its first line (`// ui/ShopScreen.kt: …`), and the Kotlin files name
theirs (`iOS: ShopView.swift`). A change to one app's screen, words or behaviour is made in the other too, or added
below. The words are the same on both (`android/app/src/main/res/values/strings.xml` and the Swift `Text("…")`; the
help text is `content/app/app.json` for both), except where a row here says otherwise or a platform's name differs
("VoiceOver" for "TalkBack", "the App Store" for "Google Play", "iPhone" for "phone" in a few places). So are the test
identifiers (`docs/DESIGN.md` › Test identifiers) and the debug launch arguments (`ios/EpicAudioGames/Debug/
DebugLaunch.swift`; Android's launch extras, `android/app/src/debug/.../DebugLaunch.kt`, have the same names).

## Both apps: answering in a chat

The games are a chat, in both apps alike. Saying or typing is the main way to answer; the bar under the transcript
has only the text box, Send and the mic. While a question is asked and has options (`Ask.buttons`), they show as
quick-reply chips at the end of the transcript, under its last line, inside what scrolls:

- **Look** (`docs/DESIGN.md` › Game): a pill (radius 24) at least 48 dp/pt tall and wide, in the surface colour with a
  2 dp/pt outline, the label as written (not uppercased) in the label style, centred.
- **Layout:** left to right, 8 apart, a new line (8 apart) when the next chip doesn't fit. A chip is as wide as its
  label and a word is never broken; a label wider than a line takes the line and wraps between words. There's no cap
  on their number (the most any question has is 5).
- **Tapping one** sends its value, as the buttons did, and the reply shows its label (B011). A tap within 500 ms of a
  new question is the last tap's double and is let go (B032).
- **When:** they appear as the question's turn starts, as the buttons did (an answer may cut the voice short), and
  they belong to that question only: answered (by a chip, by voice or typed) or moved on from, they go, and the next
  question's come. Ends keep their panel (Next chapter, Get …, Play again or Try again, Back to games): those aren't
  answers.
- **Scrolling:** without a screen reader the transcript follows the newest line, the chips, and the room it loses (the
  keyboard, the end panel), so the newest line and the chips stay in view. With VoiceOver or TalkBack on it scrolls
  only when chips, a reply or the end panel appear, so nothing moves under the player's finger.
- **Accessibility:** each chip is a button named by its label; the group is "Options" (TalkBack: a heading and a
  collection; VoiceOver: a container).
- **The Werewolf's accusation** (`ga`) offers only "List villagers", which reads the villagers in the chat; the
  player says or types a name. (B008's nine villager buttons were taken out again: tapping isn't meant to be the only
  way to play.)

## Deliberate differences

Each row: what iOS does, what Android does, why, and what pins it. Code comments cite the rows by number (`L22`), so a
row that stops being a difference keeps its number out of use.

### The game, its audio, speech and the store

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| L2 | A call, Siri or an alarm, the turn's or the mic's engine stopping itself while in use, the media services restarting, and a turn whose audio can't start at all (a call has it) all pause the game: "Carry on", also at an end or while idle. The session's events are reported even when it couldn't be made active as the game opened | A passing loss of audio focus pauses the voice and resumes it by itself; a lasting loss, focus refused, or headphones taken out pause the game (B031, B039) | iOS stops the engine and doesn't restart it, so the turn would never finish | TurnPlayerTests (`aTurnThatCantStartStalls`, `eventsAreReportedEvenIfTheSessionCantBeActive`), GameControllerTests (`aTurnWhoseAudioCantPlayWaitsForATap`), AppModelTests (`callsAndHeadphonesOutPauseTheGame`); on a device, the plan's interruption matrix |
| L22 | The mic is kept running (an input-only AVAudioEngine, `MicInput`) from when a game opens with the mic allowed until it closes; between answers its sound goes nowhere, and each answer is a new recognition request on it. Leaving the app or locking the phone doesn't pause the game | The recogniser opens the mic for each answer; a foreground service keeps the game going with the screen off (`BackgroundPlay.kt`) | iOS refuses to start recording in the background (`cannotStartRecording`), so a mic opened per answer could never listen with the phone locked | BackgroundAudioTests, AppModelTests (`theGamePlaysOnInTheBackground`), PlaythroughUITests (`testTheGamePlaysOnInTheBackground`); on a device, the phone locked |
| L23 | The lock screen's Now Playing (the game, its cover; playing while it speaks or listens). The headphones' one button (togglePlayPause) does what Magic Tap does (A2). Pause on its own (an AirPod taken out) pauses the game; play on its own carries on, or starts listening while the game waits | The game's notification and its media session: their button does what a tap on the talking circle does (`BackgroundPlay.kt`), named by `CircleAction`; none at an end, while waiting for the question, or with the mic refused | The platforms' own controls | GameControllerTests (`theHeadphonesButtonDoesWhatMagicTapDoes`, `pauseAndPlayFromTheHeadphones`, `theLockScreenShowsTheGameWhileItsOpen`); NotificationButtonTest |
| L24 | The listening sound, then the mic: the mic is already running (L22); the sound plays on the game's cue node, and audio recorded before it has been heard out is dropped (`MicInput.admit`, a host-time gate); the silence is counted from the gate | `ListenSequence`: the Bluetooth headset's route, then the sound (`Earcons`, an AudioTrack without focus), then `startListening`, once the sound has been heard out | Each platform's way to keep the sound out of the answer: iOS's mic is on all game long; Android's recogniser opens the mic itself | MicInputTests, GameControllerTests (`theListeningSoundPlaysBeforeTheMicOpens`, `theSoundPlaysHoweverTheMicOpens`, `aListenHasOneSound`), EndpointerTests (`theSilenceIsCountedFromTheGate`); ListenSequenceTest |
| L25 | The recogniser plays no sounds of its own | Google's speech service plays its own beeps (as the mic opens, and as a silent listen ends) as notification sounds: the app mutes notification sounds while it listens and gives them back 1.5 s after (`RecognizerBeep.kt`). A mute, vibrate or Do Not Disturb the player set is never touched; a phone whose notification volume is its ringer's is left alone (its beep still follows the game's sound) | Only Google's recogniser beeps, and Android has no public way to stop it | NotificationMuteTest, RecognizerBeepTest; DESIGN.md's real-phone checklist |
| L15 | Speech is SFSpeechRecognizer in the player's first English (else US English), on the device where it can be and on Apple's servers where not (D9). The app decides when an answer is over (`Endpointer`): no words for the time to answer (Settings: 6, 10 or 15 s) is a silence, words unchanged for 1.2 s (2 s with Longer and Longest) are the answer, 20 s at most. Its errors are read as Android reads its own, but trouble after an interruption or a route change never turns the mic off | SpeechRecognizer (free form, offline preferred, 5 guesses), which decides when speech has ended; when it gives up on a silent listen with at least 2 s of the time to answer left, the same listen goes on without the sound (at most 8 times; a 2 s settle hint for Longer and Longest) | iOS's recogniser listens until told to stop, and usually gives one guess where Android gives five; Android's ends a silent listen after about 5 s by itself | EndpointerTests (`theTimeToAnswerIsThePlayers`), SpeechTests; AnswerTimeTest; the timings need tuning on a device |
| L16 | The mic and speech recognition are asked for together (both are needed to listen): by onboarding's Allow microphone, or as a game opens unless the player said Not now there (`settings.micPrimed`). After "Don't Allow", iOS never asks again: the mic button and the circle say the mic is off and lead to Settings, and Settings › Microphone shows "Open phone settings" at once | The microphone (and on Android 13+ notifications) is asked for the same way; the mic button asks again while Android still will, then says the mic is off and leads to Settings (B015, B080), and Settings says "Android won't ask again…" once it has refused for good | iOS asks for each permission once, and says when it won't (.denied); Android only says so by not asking | PlaythroughUITests (`testTheMicIsAskedForAsAGameOpens`), BugReplayUITests (`testB015TheMicOffLeadsToSettings`), IntroOnboardingUITests (`testNotNowLeavesTheMicForLater`) |
| L26 | Voice speed: AVAudioUnitTimePitch after the voice's and beds' mixer, bypassed at 1× (so 1× is bit for bit what it was) | Media3's PlaybackParameters (Sonic) on the voice and every bed | Each platform's time-stretcher | TurnPlayerTests (`atTwiceTheSpeedATurnTakesHalfTheTime`), OfflineRenderTests (1× and 1.5×) |
| L27 | If the last buffer's "played back" never comes through the time-pitch, a turn finishes by its own clock 0.5 s after its end (and logs it) | Media3 reports each turn's end | AVAudioEngine's callbacks through a time-pitch are unconfirmed on a device | TurnPlayerTests |
| L28 | Outside a game, the app's short sounds (the listening sound's preview, the success sound) and the sting play in the ambient session: the silent switch mutes them, they mix with other apps' audio, and the sting is skipped while another app's audio plays (`secondaryAudioShouldBeSilencedHint`) or with the app in the background. Settings' sample of the sting plays the same way; its sample of the music plays in the spoken session (another app's audio stops for it and comes back after) and stops if the headphones come out. In a game, the short sounds play on the game's cue node, in its session | Short sounds play through an AudioTrack without audio focus, at media volume, whatever the ringer says (silent and vibrate are for rings and notifications); the sting plays without focus and is skipped while another app's music plays (`isMusicActive`); the music's sample takes the focus for a moment | iPhones keep an app's incidental sounds to the silent switch; Android's ringer mode doesn't govern media | AppAudioTests; AppAudioTest; DESIGN.md's checklist (the sting with the silent switch on, and with music playing) |
| L29 | Haptics: a rigid tap as the mic opens, a soft one as it closes, the system's success for a pack installed | TICK, LOW_TICK (Android 12+) and DOUBLE_CLICK | Each platform's own feedback; both follow Settings › Vibrate when listening starts | On a device |
| L7 | The ⋮ menu is iOS's `Menu`, anchored to its button | Material's `DropdownMenu`, dropping from the ⋮ | The platform's own control | Screenshot review |
| L9 | Nuclear War's missing clips are tracked per game (`NuclearWar.missing`) | One set on the shared `NuclearAudio` | `NuclearAudio` is immutable and shared between games | NuclearWarTests |
| L12 | The JSON reader refuses unquoted literals (`00`, `tru`); otherwise it takes what kotlinx 1.6.3 takes | kotlinx reads unquoted literals | No map or save has them; refusing them keeps the reader small | JSONTests, TextConf |
| L13 | A refunded or revoked pack is taken off the phone, once its game is closed (D11) | A refunded pack stays | The App Store revokes a refunded purchase; deleting a pack under a game playing it would break the game | StoreTests (`aRefundTakesThePackAwayOnceItsGameCloses`) |
| L18 | The keyboard stays up after sending, as on Android, and dragging the transcript down into it puts it away | The system Back button puts it away | An iPhone keyboard has no key to hide it | PlaythroughUITests (`testNoodleRushToAnEndingAndBack`) |
| L19 | A pack's zip must be stored, not compressed: a compressed or encrypted entry is refused | `ZipInputStream` inflates compressed entries | `tools/make_pack.py` writes stored entries (the audio doesn't compress), and a reader of stored zips is small | PackStoreTests (`compressedAndBrokenZipsAreRefused`) |
| L20 | "Restore purchases" asks the App Store again (`AppStore.sync`, which may ask the player to sign in); opening the Shop or the store sheet only reads the purchases again | Both read Play's purchases | Apple asks apps to sync only when the player asks | StoreTests (`aFailedDownloadIsTriedAgainLater`) |
| L21 | Buttons, cards and chips darken a little while pressed (`PressStyle`) | Compose's ripple, spreading from the finger | SwiftUI has no ripple | Screenshot review |
| L30 | A game that's loading opens: there's no way back from the spinner, which takes a moment | Back while a game loads cancels it (`AppModel.cancelOpen`) | iOS has no system Back | — |

### Screen readers, input and the look

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| A2 | **Magic Tap** (VoiceOver's two-finger double tap) is the one button wherever there is one: in a game it skips, talks, stops listening or carries on (as the talking circle and the headphones' button do); on the intro it skips; on a Help page and the welcome it's Listen or Pause. VoiceOver's escape (the two-finger scrub) closes sheets and Help pages, and leaves a game | TalkBack has no Magic Tap for apps: the **media key** is the one button (the headphones' button and the notification's, through the media session), and TalkBack's two-finger double tap reaches it where TalkBack hands it to the media session. Back closes sheets and pages, and leaves a game | The platforms' own gestures | GameControllerTests (`theHeadphonesButtonDoesWhatMagicTapDoes`), HelpTests; DESIGN.md's checklist (both, on a device) |
| A6 | **Status messages** (a purchase done, a download finished or failed, restored, the mic allowed, usage data deleted) are queued VoiceOver announcements (`A11y.announce`), never while the game listens, and shown as words too | Polite live regions (`StatusText`), and `paneTitle` on sheets and overlays (`announceForAccessibility` is deprecated in Android 16) | Each platform's way to say what changed without moving the focus | AppModelTests; StoreSheetTest, SettingsScreenTest |
| A7 | **Focus** moves to the end panel's and the Paused overlay's headings, the talking circle as a game opens, the Games heading after the intro or onboarding, each onboarding page's heading, the store sheet's and Licences' headings, 300 ms after they show (`A11y.focusDelay`); a Help topic's heading, pushed on a phone or in the help sheet as it rises, 700 ms after (`A11y.focusAfterTransition`), once iOS has moved VoiceOver to the new screen itself; a Help topic's row and Settings' Licences row take it back as their page closes | The same moments, 300 ms after (`Modifier.focusOnAppear`), for TalkBack and a keyboard; a Help page replaces the list in place, so there's no transition to wait for | iOS moves VoiceOver itself at the end of a push or a sheet | AppModelTests, HelpTests; GameScreenTest, OnboardingTest, HelpScreenTest; with VoiceOver on a device |
| A8 | **Voice Control input labels**: the talking circle answers to its name, "Skip", "Talk" and "Picture"; the mic to its name, "Talk", "Microphone" and "Mic"; a game's card to its title and "Play <title>" | Voice Access says the visible label (or the TalkBack name, which starts with it) | iOS lets a control have several names; on both, a visible label is what the screen reader says first | On a device (DESIGN.md's checklist) |
| A9 | **Keyboard shortcuts** are invisible keyboard-shortcut buttons (`ShortcutKey`), listed in the ⌘-hold overlay: ⌘1–4 the tabs; in a game Space is the one button (unless the answer box has the keys) and Escape pauses, carries on, or leaves at an end; Escape closes sheets and pages. The system draws the focus ring | `FirstKeys` offers Space to the game before anything else has it, and `Shortcuts` handle Ctrl+1–4 and Escape; Escape on a tab goes to Games, as Back does. The app draws its own 3 dp focus ring | iOS has `.keyboardShortcut` and draws the focus ring itself; Compose has neither | TabsUITests (`testTheKeyboard`); TabsTest, MainTabsTest |
| A10 | **The contrast mapping**: Increase Contrast (`colorSchemeContrast == .increased`) turns Light into Light + increased contrast and Dark into High contrast. Reduce Transparency keeps the scrims solid (they already are), Differentiate Without Colour makes the decorative edges 2 pt, and Button Shapes underlines buttons that are only words | The same palettes from Android 14+'s contrast setting (`UiModeManager.getContrast()` 0.5 or more, Medium or High) or Android 16+'s high-contrast text, followed as they change | Each platform's setting; Android has no Reduce Transparency, Differentiate Without Colour or Button Shapes | ThemeContrastTests (`thePaletteFollowsTheThemeDarkModeAndContrast`), AccessibilityAuditTests (Light with `-EpicContrast increased`); ContrastTest |
| A11 | **Bold Text** (`legibilityWeight == .bold`) draws Atkinson one weight heavier by hand: Regular as Bold, Bold as ExtraBold; the phone's font (SF) is made bolder by SwiftUI | Compose adds the phone's font-weight adjustment (Android 12+) to every weight itself, which resolves to the same faces | A named iOS font doesn't change by itself | DesignTests (`boldTextDrawsEachWeightOneHeavier`); on a device |
| A12 | **The theme** is set on the window (`overrideUserInterfaceStyle`), so the status bar, sheets, alerts and menus follow it; High contrast is a dark one | `EpicTheme` maps every Material colour role and sets the bars' icons (`WindowCompat`), sheets' too | SwiftUI's `preferredColorScheme` doesn't go back to the phone's when it returns to nil | TabsUITests (`testSettingsSetWhatTheySay`); BarIconsTest |
| A13 | **Text size**: Dynamic Type grows every style as its text style grows (`UIFontMetrics`), up to AX5, on top of Settings › Text size; the compact game layout is from the first accessibility size. Buttons that share a row (onboarding's Back and Next, the help sheet's top row, the compact answer bar's Send and Talk, the voice speed's Slower and Faster) stack when their words don't fit on a line each | The font scale, up to 200%; the compact layout from 1.6. Send and Talk stack when a word wouldn't fit (`SharedRow`), the speed stepper likewise; Back and Next stay side by side (their words always fit at 200%) | iOS's largest sizes are larger than Android's 200% | DesignTests, AccessibilityAuditTests (AccessibilityXXXL), BugReplayUITests (`testB076PanelsScrollWithTheLargestText`); GameScreenTest and the LargeText test classes |
| A14 | Settings' switches are whole-row `Toggle`s, named by their titles, the hint after | Whole-row `toggleable(role = Switch)` | The same, in each platform's control | TabsUITests (`testSettingsSetWhatTheySay`); SettingsScreenTest |
| A15 | The Paused overlay is modal (`.isModal`); a tap off its buttons carries on, by finger only with VoiceOver off (a VoiceOver double tap there is a tap at that point) | `paneTitle` "Paused"; the tap off its buttons is pointer only, TalkBack doesn't see it | VoiceOver turns a double tap on an element with no action into a tap | PlaythroughUITests, BugReplayUITests; GameScreenTest |

### The screens

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| S1 | **Tabs**: the system's `TabView`: along the bottom on an iPhone, at the top on an iPad from iPadOS 18 (the bottom before); VoiceOver says "Shop, tab, 2 of 4", and at the largest text sizes a long press shows a tab's name large (the Large Content Viewer). Unselected tabs are in the system's grey | Material's `NavigationSuiteScaffold`: a bar on compact windows, a rail on medium and expanded ones; at large text, when the labels don't fit four across, the app's own `TabRows` (icon and whole label, two or one to a row, with the same semantics) | The system's bar is what iOS players know; Material's bar breaks words at 200% | TabsUITests (`testTheFourTabsSayWhichIsSelected`), AccessibilityAuditTests (two exceptions, below); MainTabsTest, TabsTest |
| S2 | Reopening onboarding ("Show the welcome again") makes the tabs again, so each tab's scroll position is lost | Each tab's place is kept (`rememberSaveableStateHolder`) | SwiftUI keeps no tab's state outside its `TabView` | — |
| S3 | **The launch screen** (`UILaunchScreen`: navy, `LaunchLogo` at 160 pt in the middle of the whole screen, light status bar icons), then the intro draws the same emblem in the same place, a 240 pt circle round it | Android's splash screen API (navy, the 128 dp emblem), gone at once under the intro, which draws a 192 dp circle round it | Each platform's launch screen and its sizes | SmokeTests (`infoPlist`, `theLaunchLogoIsInTheApp`), IntroOnboardingUITests; IntroScreenTest; by eye on a device |
| S4 | **The intro** is one element, "Epic Audio Games", with the action "Skip intro"; a tap, Magic Tap, the two-finger scrub, Escape or Space skips it. The window is kept dark while it shows | One element with "Skip intro"; a tap, Escape, Space or Back skips it; its bar icons are light | Each platform's ways to dismiss | IntroOnboardingUITests (`testTheIntroIsOneElementThatATapSkips`); IntroScreenTest |
| S5 | **Onboarding's microphone page** says iOS will also ask about speech recognition; the usage-data line announces "Usage data is on." when it's turned back on | It says Android 13+ will also ask about notifications (the game's notification has the circle's button) | What each system asks | IntroOnboardingUITests; OnboardingTest |
| S6 | **Help** shows its list and a topic side by side from a regular width (an iPad, 600 pt or wider: `NavigationSplitView`); on a phone a topic is pushed, with the system's Back ("Help") | Side by side from an expanded width (840 dp: `ListDetailPaneScaffold`); on narrower windows the page takes the list's place, with "All help topics" | SwiftUI's split view follows the size class | HelpUITests (`testATopicHasItsHeadingListenWordsAndLinks`); HelpScreenTest |
| S7 | **Listen** on a Help page and the welcome has the media-session trait (VoiceOver stays quiet after the tap) and Magic Tap plays or pauses it | State "Playing"; TalkBack's own feedback for the tap, then the voice 400 ms later (both apps wait 400 ms with a screen reader) | iOS has the trait; Android hasn't | HelpTests; HelpScreenTest |
| S8 | **The store sheet** is a sheet with detents (large at accessibility sizes), its own Close and Escape | A full-height bottom sheet, at most 640 dp wide and below the status bar, with Close, Back and Escape | The platforms' own sheets | PlaythroughUITests (`testTheStoreSheet`); StoreSheetTest |
| S9 | **Settings › Licences** is pushed, with the system's Back ("Settings") | A page in place with its own Back (`licences-back`) | The platform's own navigation | TabsUITests (`testLicencesAndBack`); SettingsScreenTest |
| S10 | **A pack's row** has three states more: "Installing…", "Waiting for Wi-Fi" with "Download now", and "Waiting for a connection" | Installed, Downloading, Bought, Payment pending, Buy or Get | iOS downloads packs in a background session, which can wait for Wi-Fi or a connection and installs as a step of its own | PackRowsTests; PackUiStateTest |
### iPad and Android tablets, Mac and Chromebooks

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| T1 | Width classes come from the size class and the window's width (`Window.swift`, measured with the keyboard down): compact under 600 pt, medium to 839, expanded from 840. The Games grid (two columns, cards up to 480 pt) and the two-pane game (expanded, or medium in landscape) follow them, as on Android | `currentWindowAdaptiveInfo()` from material3-adaptive, the same breakpoints | Each platform's window size | AccessibilityAuditTests (`testTheGameListAsAGridOnAnIPad`, `testAGameInTwoPanesOnAnIPad`); the Tablet test classes |
| T2 | An iPad window switching between one pane and two (turning, Split View, Stage Manager) keeps what's being typed (GameView holds it) | The answer bar keeps it (`rememberSaveable`) | The same, in each platform's way | — |
| T3 | iPadOS may open a second window of the app (the generated scene manifest's default); both would show the same model (the same tab and game) | One window of the app | Not decided yet: turning it off is `UIApplicationSupportsMultipleScenes`, to check with Xcode | On an iPad |
| T4 | The iPad app runs on Apple-silicon Macs and Apple Vision Pro as "Designed for iPad" (`App.xcconfig`); usage data's form_factor is read once at launch: tablet for an iPad (and Vision), desktop on a Mac | Chromebooks run the Android app (form_factor desktop, `FEATURE_PC`), read with each event, since a foldable can open | Each platform's other devices | EventsTests (`theKindOfDeviceIsCoarse`); EventsTest |

### Watches

The Apple Watch app (`ios/EpicWatch`, `docs/WATCH.md`) and the Wear OS app (`android/wear`, `docs/WEAR_OS.md`) are the
same remote: the game's title, its state in words, one big button named by `CircleAction`, Pause while it can pause,
the end panel's heading and "Choose what's next on your phone/iPhone." at an end, "Open a game on your phone/iPhone"
with none, the button dimmed with the mic not allowed or before the question, "Listening…", a buzz as the mic opens and
another as it closes (none on the first state or as the game closes), the failure line ("Can't reach your
phone/iPhone. Keep it close, then try again."), the `watch-*` identifiers and the demo states (`-EpicWatchDemo`,
`EpicWatchDemo`). A press of the big button that crosses with an end does nothing on both (`WatchBridge.perform`,
`WearBridge.perform`).

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| W1 | WatchConnectivity: the state as the application context (and a message while the watch app is in front); the buttons as messages, which launch the iPhone app in the background if it isn't running, and it then tells the watch no game is open | The Wearable Data Layer: the state as an urgent data item; the buttons as messages to the `WearCommands` service, which starts the app's process and, with no app open, tells the watch no game is open without opening the app's screen | Each platform's link | WatchBridgeTests, WatchLinkTests; WearBridgeTest, WearLinkTest |
| W2 | The watch's inbox can buzz for a change it missed while away, as it hears again | Coming back to its screen, the watch takes the latest state without a buzz | WatchConnectivity has no "caught up" moment | WatchLinkTests; WatchAppTest |
| W3 | High contrast on the watch when it asks for more contrast; otherwise the iPhone's Dark palette | The Dark palette always (every text pair 7:1 already) | Wear OS has no contrast setting apps can read | docs/WATCH.md's checks on a watch; WatchAppTest |
| W4 | The big button also answers Magic Tap and, from watchOS 11, the double-tap gesture | Touch, or TalkBack's double tap | Wear OS has neither for apps | On a watch |
| W5 | With the wrist down (Always On), the big button is drawn outlined | In ambient mode the button is outlined and the background black | Each watch's low-power look | WatchScreenTest (ambient) |
| W6 | No watch app on an iPad, a Mac or Vision Pro (no WatchConnectivity there) | The Data Layer quietly absent on a phone without Google Play services | Where each link exists | — |

### Usage data

The same events, properties and rules on both (`web/analytics/events.json`; `docs/DESIGN.md` › Usage data); on both,
nothing is sent on the first run until onboarding is over, `EpicAnalytics off` turns usage data off for a launch, and
debug builds send nothing unless given a server.

| # | iOS does | Android does | Why | Pinned by |
|---|---|---|---|---|
| U1 | Going to the background, the app asks iOS for a moment of background time until the send is over | No background time needed | iOS suspends an app mid-request | UsageDataTests (`goingOffScreenSaysWhenTheSendIsOver`) |
| U2 | Off in the unit tests' host (`XCTestConfigurationFilePath`) | Off in Firebase Test Lab (Play's pre-launch report) and in tests | Where each platform's automated runs are | EventsTests (`whereUsageDataGoes`); UsageDataTest |
| U3 | Purchases: the App Store has no "owned" (it sells a bought pack again for nothing), so iOS reports purchased; purchase_start goes as the App Store's sheet shows, for a product whose price is known | Play's "owned" is reported | The stores' own answers | StoreTests; EventsTest |
| U4 | mic_permission with where=game only when iOS really asks | The permission launcher's answer, even an automatic refusal | iOS knows whether it will ask | GameEventsTests |
| U5 | Device text (the iOS version, the language): whole characters up to 64 UTF-16 units; a queue line that isn't JSON is skipped | Emoji and other surrogate characters dropped | The same limit, each platform's strings | EventsTests (`timesIdsAndTextAreAsTheServerReadsThem`); EventsTest |
| U6 | A mistake in the app's own events stops a Debug build (`assertionFailure`) | Throws in a debug build | The same "crash in debug" | UsageDataTests (`aMistakeInTheAppsOwnEventsIsCaught`); UsageDataTest |

### Debug launch arguments

The same names and meanings on both. iOS only: `-EpicContrast increased` (the phone's Increase Contrast, which a UI
test can't turn on), `-EpicHoldIntro YES` (the intro held for the audit), `-EpicVoiceOver YES` (onboarding as with
VoiceOver on), `-EpicLab YES` (the Audio Lab) and `-settings.<key> <value>` (a setting for one launch). Android only:
the `EpicShots` log lines the screenshot and preview tools wait for (iOS's UI tests watch the screen instead).

### Differences that are gone

Numbers no longer listed (L1, L3, L4, L5, L6, L8, L11, L14, L17, A1, A3, A4, A5) were differences that are gone: both
apps now do what the iOS column said (an engine error is a note and back to the list; a second listen does nothing; a
turn's first beds start once; a missing or broken clip is passed over; no sale without a pack server; the loading
overlay takes the touches; a save that can't be opened starts the game afresh; a pack installed while its own game
waits at the end it unlocks opens the game there with Next chapter). L17's dimmed back arrow is gone: both apps' Paused
overlay has Carry on, How to play and Leave game. A1 and A3 apply to both apps: with a screen reader on, the game
doesn't open the mic by itself (Settings › Microphone, `MicPolicy`), and the mic opens with the listening sound on
both; the talking circle is named "Stop listening" while it listens, a line reads "Gribbo: …" and a reply "You said:
…" (`CircleAction`, `FeedItem.readAs`). A4's Dynamic Type caps are gone (nothing stops growing), and A5's Reduce Motion
is honoured on both (the phone's setting or the app's). Code comments still cite them for that behaviour.

### The accessibility audit

`EpicAudioGamesUITests/AccessibilityAuditTests.swift` runs `performAccessibilityAudit()` on the game list, a game
asking a question (Noodle Rush, its chips showing), an end panel, the store sheet, the Shop, Settings (four scroll
positions), Licences and Help; the list and a game in each theme and a game at AccessibilityXXXL; then, in each of
`docs/DESIGN.md`'s looks (Dark, Light, High contrast, Light with Increase Contrast, AccessibilityXXXL), the intro, each
onboarding page, Help's list and a topic, Settings, the Shop, and a game listening with its help sheet and its pause;
on an iPad also the Games grid and the two-pane game. Android's counterpart is the instrumented suite with
`enableAccessibilityChecks()` (Looks.kt: the same looks at 200% and on a tablet). What the audit lets through, and why:

- **Contrast**, for transcript lines (text only) scrolled out of the transcript's view: the audit measures what's
  drawn over them there (the circle, the header), not their words on their bubble.
- **Text clipped**, for a transcript line partly scrolled out of view at the largest text: it scrolls into view whole.
- **Contrast** and **Dynamic Type**, for a tab in the system's tab bar: it draws the tabs not picked in its own grey
  (which tab is picked is also its filled symbol, and VoiceOver says "Selected"), and keeps its labels' size, showing a
  tab's name large on a long press instead (the Large Content Viewer).
- **Contrast**, **text clipped** and **hit region**, for a tab's content scrolled under the tab bar (never the tabs or
  the bar themselves, and not with the store sheet up): the audit measures the bar drawn over it, and it can't be
  touched until it's scrolled out from under it.
- **Text clipped**, for the text box: it's one line, and what's typed scrolls sideways in it; it grows with the text
  size.
- **Text clipped**, for the store sheet's and the help sheet's rows below their foot: the store sheet is as tall as
  what's in it, up to the screen, and the help sheet the screen's height; with the largest text they scroll to them.
- **Element detection**, with a sheet up and no element named: what's under the sheet showing around it (iOS 26 floats
  it), which VoiceOver rightly doesn't reach while the sheet is up.

The old exceptions for the end panel's and the store sheet's outlined titles and the Dynamic Type caps are gone with
them. The audits added for the intro, onboarding, Help, Settings, the Shop and the iPad haven't run yet: a new issue
the app means gets its exception here and in `Exceptions.allows`, with its reason.

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
  back at that end, with "Welcome back!" and Next chapter (B001); any other end, and a plain quit, starts the game
  again keeping the map's `keep` variables, as Play again's `restart()` does (B002, B027): Alien Customs keeps its
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
  quality: the voice is call quality on Bluetooth headphones for as long as a game is open. Android routes a headset's
  mic through its Bluetooth call link only while it listens (`HeadsetMic.kt`).
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
`keep` variables after an end, the double `listen()`, a missing clip holding a turn up, the packs left out of Auto
Backup, VoiceOver's D8 for TalkBack, and the circle's "Stop listening" with replies read "You said: …") is done in both
apps. What's left:

- `NuclearAudio.missing` shared across games (L9).
