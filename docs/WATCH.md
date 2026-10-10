# The Apple Watch app

A remote for the game on the iPhone (docs/DESIGN.md › Watches). The iPhone still plays the audio and listens (a watch
has no speech recognition for apps, and the games are about 190 MB). The watch shows:

- the game's title, as a heading;
- what the game is doing, in words: "Speaking", "Your turn", "Listening…", "Paused" or "Wait for the question", or at
  an end the end panel's heading ("Chapter complete", "Game over", "The end");
- one big button, named as on the iPhone (the talking circle's `CircleAction`: "Skip", "Talk", "Stop listening",
  "Carry on"), which does what tapping the picture does;
- "Pause", while there's something to pause;
- at an end, no button but "Choose what's next on your iPhone.", because the end panel's choices are on the iPhone;
- "Open a game on your iPhone" when no game is open.

The watch buzzes as the microphone opens (watchOS's start haptic) and buzzes differently as it closes (stop). This is
the cue for a player who can't hear the listening sound. Android's Wear OS app does the same through the Wearable
Data Layer: `WearBridge.kt` and `android/wear` (docs/WEAR_OS.md).

Nothing goes to our server from the watch, and the watch app collects nothing. It talks only to the iPhone, device to
device, through WatchConnectivity. The App Privacy answers don't change.

## What's where

| File | What it is |
|---|---|
| `ios/EpicAudioGames/Watch/WatchBridge.swift` | The iPhone's side. `WatchBridge` follows the open game and tells the watch, and does what its buttons ask. `WatchSession` is WatchConnectivity's session. `AppModel` starts it. |
| `ios/EpicEngine/Sources/EpicAppCore/WatchLink.swift` | What goes between them, shared: `WatchState`, `WatchAction`, `WatchCommand`, and the watch's `WatchInbox` (newest state first, and the buzzes). |
| `ios/EpicWatch/WatchLink.swift` | The same file again, word for word, because the watch app links no package. `WatchLinkTests` fails if the two differ: after changing one, copy it over the other. |
| `ios/EpicWatch/EpicWatchApp.swift`, `WatchView.swift` | The watch app and its one screen. |
| `ios/EpicWatch/PhoneLink.swift` | The watch's side of WatchConnectivity. It takes the iPhone's states in, plays the haptics and sends the buttons. |
| `ios/EpicWatch/WatchDemo.swift` | Debug builds only: `-EpicWatchDemo <state>` shows a game's state without an iPhone, for screenshots. |
| `ios/EpicWatch/Assets.xcassets` | The app icon, the iPhone app's 1024 image (watchOS rounds it, and the emblem fits inside the circle), and the gold accent. |
| `ios/EpicWatch/PrivacyInfo.xcprivacy` | No tracking, nothing collected, no required-reason APIs. |
| `ios/EpicWatch/Watch.xcconfig` | The watch target's build settings, as `ios/Config/App.xcconfig` is the iPhone app's. |
| `ios/EpicEngine/Tests/EpicAppCoreTests/WatchLinkTests.swift` | The messages both ways, through a property list as WatchConnectivity carries them; the inbox; the copy. |
| `ios/EpicAudioGamesTests/WatchBridgeTests.swift` | What the watch is told as a game goes, its buttons, and the app's model with a test's link. |

## How it works

**iPhone to watch.** Whenever what the watch shows changes, `WatchBridge` tells `WatchSession`. It watches the game
with Observation, because the screen may not be drawn while the phone is locked. `WatchSession` sends the state two
ways:

- as the **application context**, which the watch reads as its app opens; the newest one replaces the last;
- while the watch app is in front (`isReachable`), as a **message** too, so it shows at once.

Nothing goes until the session is active and a paired watch has the app. The session says when that changes:
activation, `sessionWatchStateDidChange`, and reachability coming back. Each time, the whole state goes again.

The state is a dictionary of property-list values (`WatchState.context(at:)`):

| Key | Type | Value |
|---|---|---|
| `title` | string | the open game's title; empty when none is open |
| `state` | string | the words above; empty when no game is open |
| `action` | string | `carryOn`, `skip`, `stopListening`, `talk`, `micRefused`, `noRecognition` or `wait` (CircleAction's case names); empty when there's nothing to press. The watch picks the button's icon by it. |
| `label` | string | the big button's name, `CircleAction.label`; empty when there's no button |
| `enabled` | bool | the big button can do something |
| `listening` | bool | the microphone is open |
| `canPause` | bool | a game is open, not paused and not at an end |
| `at` | number | when the iPhone made it, in seconds since 1970 |

The context and the messages can arrive in either order, so the watch shows the state with the newest `at`. A state
more than a minute older than the one showing can only mean the iPhone's clock was put back, so it is taken too.

**Watch to iPhone.** Each button sends `["command": "primary"]` or `["command": "pause"]` with `sendMessage`. If the
iPhone app isn't running, the message launches it in the background. The phone then has no game open, so the watch
soon says so. `WatchBridge.perform` handles the two commands:

- **primary** does what Magic Tap does, the way the headphones' button has it (`NowPlaying.press`): it skips the voice,
  carries on after a pause, or starts or stops listening (`GameController.magicTap(talk:)`). It can't show the
  microphone's permission question, which only the iPhone's screen can. So with the microphone not allowed, the watch
  shows the button dimmed, still named "Talk (the microphone is off)", which says why.
- **pause** pauses the game, as Escape and the lock screen's pause do (`GameController.pause()`). It does nothing over a
  pause or at an end, and the watch hides Pause then.

If the iPhone can't be reached, a press buzzes a failure and the watch says "Can't reach your iPhone. Keep it close,
then try again." until the iPhone is heard from again.

**Haptics.** The watch buzzes start when `listening` turns on and stop when it turns off. There is no buzz for the
first state the watch gets as its app opens, nor when the game closes: leaving a game plays no sound on the iPhone
either.

**For every player.** The watch's text styles follow its text size and Bold Text. Text wraps, never cut short, and the
page scrolls. The colours are the iPhone's Dark palette, or High contrast when the watch asks for more contrast. Every
text pair is at least 7:1. Each state is in words, and the big button has an icon as well, never colour alone.

VoiceOver reads the title as a heading, then the state, then the buttons. Magic Tap (two fingers, double tap) presses
the big button. So does the double-tap gesture, on watches that have it (watchOS 11 and later). With the wrist down
(Always On), the big button is drawn outlined, so the screen isn't left bright.

## Adding the watch target (once, on the Mac, with Xcode 26)

The project file isn't edited by hand; Xcode makes the target. Do these steps once, then commit `project.pbxproj` and
the new scheme.

1. `git pull`, then open `ios/EpicAudioGames.xcodeproj`.
2. **File › New › Target…**, choose **watchOS › App**, then **Next**.
3. Options:
   - **Product Name:** `WatchTemplate`. This is a temporary name, so that the template's folder can't land in
     `ios/EpicWatch`. You rename the target in step 6.
   - **Team:** yours.
   - **Embed in Companion App** (Xcode may call it the companion or "Watch App for Existing iOS App"): **EpicAudioGames**.
     Xcode then adds an "Embed Watch Content" phase and a dependency to the iPhone app.
   - SwiftUI and Swift, no notification scene, no tests. Then **Finish**, and **Activate** the scheme if asked.
4. Xcode has made a folder for the template, named `WatchTemplate` or `WatchTemplate Watch App`, with its own app file,
   `ContentView.swift`, `Assets.xcassets` and maybe `Preview Content`. Select that folder in the Project navigator,
   press Delete, and choose **Move to Trash**. Check in Finder that `ios/EpicWatch` is untouched.
5. Add our folder: right-click the project (the blue EpicAudioGames icon), choose **Add Files to "EpicAudioGames"…**,
   and pick `ios/EpicWatch`. Use **Reference files in place**, **Create folders**, and tick only the new watch target
   under **Targets** (not EpicAudioGames, nor the test targets). It should show as a blue folder (a synchronized
   folder). If it shows as a yellow group, right-click it and choose **Convert to Folder**.
6. Rename the target: in the TARGETS list, select the watch target, press Return, and type `EpicWatch`.
7. Target membership:
   - Select the `EpicWatch` folder. In the File inspector, **Target Membership** must be **EpicWatch** only. The
     iPhone app must not compile these files: it has its own `WatchLink.swift` in EpicAppCore.
   - Select `Watch.xcconfig` inside it and untick **EpicWatch** under Target Membership. It's a build-settings file,
     not a resource, and Xcode records the exception. If the box is already unticked or greyed out, leave it.
8. Base configuration: select the project (PROJECT EpicAudioGames) › **Info** › **Configurations**. Under both Debug
   and Release, set the EpicWatch row to **Watch** (`EpicWatch/Watch.xcconfig`). The iPhone app's rows stay on **App**.
9. Delete the template's own values that would override Watch.xcconfig and Base.xcconfig. In the EpicWatch target's
   **Build Settings**, choose **All** and **Levels**. Where the EpicWatch column shows a value for one of these
   settings, select the row and press Delete:
   - Swift Language Version (`SWIFT_VERSION`)
   - Default Actor Isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`)
   - Approachable Concurrency (`SWIFT_APPROACHABLE_CONCURRENCY`)
   - watchOS Deployment Target (`WATCHOS_DEPLOYMENT_TARGET`)
   - Product Bundle Identifier (`PRODUCT_BUNDLE_IDENTIFIER`)
   - Product Name (`PRODUCT_NAME`)
   - Marketing Version (`MARKETING_VERSION`)
   - Current Project Version (`CURRENT_PROJECT_VERSION`)
   - Development Team (`DEVELOPMENT_TEAM`): it comes from `Local.xcconfig`, as the iPhone app's does
   - Bundle Display Name (`INFOPLIST_KEY_CFBundleDisplayName`)
   - WatchKit Companion App Bundle Identifier (`INFOPLIST_KEY_WKCompanionAppBundleIdentifier`)
   - Development Assets (`DEVELOPMENT_ASSET_PATHS`): it pointed into the folder deleted in step 4

   Leave any other values the template set, such as code signing.
10. Check the **Resolved** column for EpicWatch:

    | Setting | Resolved |
    |---|---|
    | Base SDK | watchOS |
    | Supported Platforms | watchOS |
    | watchOS Deployment Target | 10.0 |
    | Swift Language Version | Swift 6 |
    | Default Actor Isolation | MainActor |
    | Product Bundle Identifier | `com.epicaudiogames.app.watchkitapp` |
    | Product Name | EpicWatch |
    | Marketing Version / Current Project Version | the iPhone app's (Base.xcconfig) |
    | WatchKit Companion App Bundle Identifier | `com.epicaudiogames.app` |
    | Supports Running Without iOS App Installation (General tab) | No |
    | Skip Install | Yes |

11. **Signing & Capabilities** for EpicWatch: **Automatically manage signing**, with the same team. The watch app
    needs no capabilities: WatchConnectivity needs no entitlement.
12. Schemes: open **Product › Scheme › Manage Schemes…**. Rename the watch target's scheme to `EpicWatch` and tick
    **Shared**, so it's in git as `xcshareddata/xcschemes/EpicWatch.xcscheme`. The EpicAudioGames scheme stays as it
    is: building the iPhone app builds the watch app and embeds it.
13. Build both:
    - the EpicWatch scheme for an Apple Watch simulator;
    - the EpicAudioGames scheme for an iPhone simulator.

    In the iPhone app target's **Build Phases**, **Embed Watch Content** must list `EpicWatch.app`, and **Target
    Dependencies** must include EpicWatch. If they're missing (the template wasn't given the companion), add EpicWatch
    under Target Dependencies. Then add a **New Copy Files Phase** named Embed Watch Content: Destination **Products
    Directory**, Subpath `$(CONTENTS_FOLDER_PATH)/Watch`, with `EpicWatch.app` in it.
14. Check the built watch app's Info.plist:

    ```
    plutil -p "$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-watchsimulator/EpicWatch.app/Info.plist' | head -1)"
    ```

    It needs these values:
    - `CFBundleIdentifier` com.epicaudiogames.app.watchkitapp
    - `CFBundleDisplayName` Epic Audio Games
    - `WKApplication` true
    - `WKCompanionAppBundleIdentifier` com.epicaudiogames.app
    - `WKRunsIndependentlyOfCompanionApp` false
    - `MinimumOSVersion` 10.0
    - `CFBundleShortVersionString` and `CFBundleVersion` the same as the iPhone app's

    Xcode adds `WKApplication` to a watchOS app by itself. If it's missing, add
    `INFOPLIST_KEY_WKApplication = YES` to Watch.xcconfig.
15. Commit `ios/EpicAudioGames.xcodeproj/project.pbxproj` and the EpicWatch scheme.

**fastlane needs no change.** `fastlane ios beta` archives the EpicAudioGames scheme for `generic/platform=iOS`, which
builds the watch app and embeds it. It also passes `CURRENT_PROJECT_VERSION` to every target, so the two builds
match, as the App Store requires. Its automatic signing with `-allowProvisioningUpdates` registers the watch app's
App ID (`com.epicaudiogames.app.watchkitapp`) and makes its profile.

## Testing with a paired simulator

You need the watchOS simulator: in Xcode, open **Settings › Components** and get watchOS if it isn't there. Xcode
then has iPhone and Apple Watch simulators already paired. `xcrun simctl list pairs` lists them, and Xcode's
**Window › Devices and Simulators** can make a new pair.

1. Unit tests:

   ```
   swift test --package-path ios/EpicEngine --filter WatchLinkTests
   xcodebuild test -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:EpicAudioGamesTests/WatchBridgeTests
   ```

   Use the name of any iPhone simulator you have. WatchBridgeTests' last test opens Noodle Rush with the app's own
   model. Every build has the games' maps (`scripts/bundle_content.sh`), so it runs without the audio as well.
2. Run the iPhone app on the paired iPhone simulator, with the answers scripted, since a simulator has no microphone.
   The scripted listener hears one entry at each listen. `-settings.micAuto never` keeps the microphone from opening
   by itself, so that the watch's Talk opens it. In the EpicAudioGames scheme, open **Edit Scheme › Run ›
   Arguments** and add:

   ```
   -EpicNoIntro YES -EpicSkipOnboarding YES -EpicAnalytics off -EpicHear "yes|yes|yes|yes" -settings.micAuto never
   ```

3. Run the EpicWatch scheme on the paired watch (its destination reads "Apple Watch … via iPhone …").
4. Check:
   - With no game open, the watch says "Open a game on your iPhone".
   - Open Noodle Rush on the iPhone. The watch shows "Noodle Rush", "Speaking" and a **Skip** button.
   - **Skip** stops the voice on the iPhone. The watch shows "Your turn" and **Talk**.
   - **Talk** opens the microphone on the iPhone, with its listening sound. The watch shows "Listening…" and **Stop
     listening**. A moment later the scripted listener answers, and the game speaks again.
   - **Pause** shows the iPhone's Paused overlay. The watch shows "Paused" and **Carry on**, and Pause goes.
     **Carry on** asks the question again.
   - At a chapter's end the watch shows "Chapter complete" and "Choose what's next on your iPhone.", with no big
     button.
   - Back to games on the iPhone: "Open a game on your iPhone" again.
   - Quit the iPhone app in the simulator, then press a watch button. The iPhone app launches in the background, and
     the watch says to open a game.

   A simulator plays no haptics; check those on a real watch.
5. Screenshots for the App Store (Debug build): launch the watch app in a game's state without an iPhone, then save
   the simulator's screen:

   ```
   xcrun simctl launch <watch udid> com.epicaudiogames.app.watchkitapp -EpicWatchDemo listening
   xcrun simctl io <watch udid> screenshot watch-listening.png
   ```

   The states are `speaking`, `turn`, `listening`, `paused`, `wait`, `refused` (the microphone off), `end` and
   `none`. App Store Connect lists the Apple Watch screenshot sizes. A screenshot of a simulator of that watch is the
   right size.

## Checking on a real watch

Before the watch app is mentioned in a listing, check all of these on a real Apple Watch paired with a real iPhone:

- **Install.** The watch app comes with the iPhone app (or from the Watch app on the iPhone › Available Apps, which
  the Help topic "Using a watch" points to). Its name is "Epic Audio Games", and the round icon shows the whole
  emblem.
- **Haptics.** The start and stop buzzes are strong enough to notice during a game and clearly different from each
  other. The start buzz comes with the iPhone's listening sound, not noticeably after it. Try it with the phone in a
  pocket and the screen off.
- **Wrist down.** The watch app stays in front for a while after the wrist drops (Settings › General › Return to Clock
  › Epic Audio Games: "Return to App" keeps it there). Check:
  - whether the buzzes still come with the wrist down;
  - that the screen is dim with the big button outlined (Always On);
  - that the state is right again as soon as the wrist comes up.
- **VoiceOver on the watch.** The title is read as a heading, then the state, then each button by its name. A dimmed
  button is read as dimmed. Magic Tap (two fingers, double tap) presses the big button.
- **Double tap** (Apple Watch Series 9 or later, or Ultra 2, on watchOS 11): finger and thumb, twice, presses the big
  button.
- **Text.** At the largest text size and with Bold Text, nothing is cut short and the page scrolls. Check also with
  increased contrast, if the watch has the setting.
- **Phone locked.** The game plays on in the pocket, and both watch buttons work.
- **iPhone app not running.** A press starts it in the background, and the watch then says to open a game.
- **iPhone out of reach.** A press buzzes a failure, and the watch says "Can't reach your iPhone…". It clears once the
  iPhone is back.
- **Microphone not allowed** on the iPhone. The watch shows "Talk (the microphone is off)", dimmed.
- **Now Playing.** The system's Now Playing on the watch still works alongside our app, and its pause and play act on
  the game.
- **Battery.** After an hour of play with the watch app in front, check how much battery the watch used.

## Notes for the listing and the other app

- **Screenshots.** When a build with the watch app goes to App Review, App Store Connect wants Apple Watch
  screenshots; TestFlight doesn't. See step 5 of Testing.
- **Privacy.** The watch app collects nothing, so the App Privacy answers and the iPhone app's PrivacyInfo don't
  change.
- **Differences from the Wear OS app,** for docs/IOS_PARITY.md:
  - With the microphone not allowed, the iPhone sends the big button as dimmed, because only the iPhone can ask for
    the microphone.
  - The words for listening are "Listening…", as on the status line.
  - At an end, the watch shows the end panel's heading.
