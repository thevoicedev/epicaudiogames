# The Wear OS app

A remote for the game on the phone (docs/DESIGN.md › Watches). The phone still plays the audio and listens (a watch
has no speech recognition for apps, and the games are about 190 MB). The watch shows:

- the game's title, as a heading;
- what the game is doing, in words: "Speaking", "Your turn", "Listening…", "Paused" or "Wait for the question", or at
  an end the end panel's heading ("Chapter complete", "Game over", "The end");
- one big button, named as on the phone (the talking circle's `CircleAction`: "Skip", "Talk", "Stop listening",
  "Carry on"), which does what the headphones' button does, the same as tapping the picture;
- "Pause", while there's something to pause;
- at an end, no button but "Choose what's next on your phone.", because the end panel's choices are on the phone;
- "Open a game on your phone" when no game is open.

The watch buzzes as the microphone opens (one long, strong buzz) and differently as it closes (two short ones). This
is the cue for a player who can't hear the listening sound. The Apple Watch app does the same through WatchConnectivity
(docs/WATCH.md).

Nothing goes to our server from the watch, and the watch app collects nothing. It talks only to the phone, device to
device, through Google Play services' Data Layer. The Data safety answers don't change (see Shipping).

## What's where

| File | What it is |
|---|---|
| `android/app/.../WearBridge.kt` | The phone's side. `WearBridge` follows the open game and tells the watch, and does what its buttons ask. `DataLayerLink` keeps the state as a data item. `WearCommands` is the service Play services hands the watch's messages to. `AppModel.wear` starts it. |
| `android/app/src/main/res/values/wear.xml` | The phone app's capability on Wear OS's network (`epic_audio_games_phone`): the watch sends its buttons to the phone that has it. |
| `android/app/src/main/AndroidManifest.xml` | `WearCommands`, for messages to `/game-command`. |
| `android/wear/link` (`:wear:link`) | What goes between them, plain Kotlin used by both apps: `WearState`, `WearAction`, `WearCommand`, the watch's `WearInbox` (newest state first, and the buzzes), and the paths (`WearLink`). |
| `android/wear` (`:wear`) | The watch app: `WatchActivity` (one screen, ambient mode), `PhoneLink` (the Data Layer: states in, buttons out), `WatchScreen` (Compose for Wear OS, Material 3) with `WatchColors`, `Buzz` (the haptics). |
| `android/wear/src/debug/.../WatchDemo.kt` | Debug builds only: `EpicWatchDemo <state>` shows a game's state without a phone, for screenshots. |
| `android/wear/src/main/res/mipmap-*` | The phone app's adaptive icon, copied byte for byte (a test checks it): Wear OS shows it in a circle, and the emblem fits inside. |
| `android/wear/link/src/test` | `WearLinkTest`: the state both ways as plain values, the names, the inbox. |
| `android/app/src/test/.../WearBridgeTest.kt` | What the watch is told as a game goes, when, its buttons, and that the manifest and capability match the watch app's. |
| `android/wear/src/test`, `src/testDebug` | `WatchAppTest`: the icon, the colours (the phone's Dark palette, every text pair 7:1 or more), the buzzes, the words. `WatchScreenTest`: the screen in every state on a large and a small round watch, as TalkBack finds it, under Robolectric. |

## How it works

**Phone to watch.** Whenever what the watch shows changes, `WearBridge` tells `DataLayerLink`. It follows the game with
`snapshotFlow`, because the screen may not be drawn while the phone is locked. `DataLayerLink` puts the state as one
data item at `/game-state`, marked urgent so it goes at once, which Google Play services copies to the phone's watches.
The watch app reads it as its screen comes up and hears each change while the screen is up.

Nothing goes until Play services says the phone has Wear OS's Data Layer. On a phone without it (no Wear OS or Pixel
Watch app, no Google Play services) the app logs `no Wear OS link on this phone` once (`adb logcat -s WearBridge`) and
never asks again while it runs. When the app's screen goes for good (its model cleared), the watch is told that no game
is open.

The data item's values (`WearState.toMap`; iOS's keys, so the two docs read alike):

| Key | Type | Value |
|---|---|---|
| `title` | string | the open game's title; empty when none is open |
| `state` | string | the words above; empty when no game is open |
| `action` | string | `carryOn`, `skip`, `stopListening`, `talk`, `micRefused`, `noRecognition` or `wait` (CircleAction's names, as iOS spells them); empty when there's nothing to press. The watch picks the button's icon by it. |
| `label` | string | the big button's name, `CircleAction.label`; empty when there's no button |
| `enabled` | boolean | the big button can do something |
| `listening` | boolean | the microphone is open |
| `canPause` | boolean | a game is open, not paused and not at an end |
| `at` | long | when the phone made it, in milliseconds since 1970 |

The watch reads the latest item as it opens while changes come in, so it shows the state with the newest `at`. A state
more than a minute older than the one showing can only mean the phone's clock was put back, so it's taken too. If the
watch was paired with another phone before, that phone's item is older, and the newest is taken.

**Watch to phone.** Each button sends a message to `/game-command` with the text `primary` or `pause`, to the reachable
phone node that has the capability `epic_audio_games_phone` (a nearby one first). Play services hands it to the phone's
`WearCommands` service, starting the app if it isn't running. `WearBridge.perform` then, on the main thread:

- **primary** does what the headphones' button does (`BackgroundPlay`'s tap: `GameController.circle()`): it carries on
  after a pause, skips the voice, or starts or stops listening. It can't show the microphone's permission question,
  which only the phone's screen can. So with the microphone not allowed, the watch shows the button dimmed, still named
  "Talk (the microphone is off)", which says why. Before the question it's dimmed too, as the circle is. At an end a
  press does nothing (the watch has no button then; one sent just before it heard is let go).
- **pause** pauses the game, as the lock screen's pause does (`GameController.pause()`). It does nothing over a pause
  or at an end, and the watch hides Pause then.

If the app wasn't open (no model), no game is open: `WearCommands` tells the watch so, in case its state is one left
from before the app was stopped. If no phone can be reached, or the message doesn't go, a press buzzes a failure (three
light buzzes) and the watch says "Can't reach your phone. Keep it close, then try again." until the phone is heard from
again (a new state, or the phone back in reach).

**Haptics.** The watch buzzes as `listening` turns on and again as it turns off: one long buzz at full strength, then
two short ones, told apart by their rhythm as well as their strength (`Buzz.kt`). There is no buzz for the first state
the watch gets as its screen opens, for a state it catches up with when its screen comes back, nor when the game
closes: leaving a game plays no sound on the phone either. They play as media vibrations (a game's), which the
watch's touch-vibration setting doesn't turn off.

**For every player.** The text is Compose for Wear OS's type, so it follows the watch's font size; it wraps, never cut
short, and the list scrolls by touch or with the crown. The colours are the phone's Dark palette, and every text pair
is at least 7:1. Each state is in words, and the big button has an icon as well, never colour alone.

TalkBack reads the title as a heading, then the state, then the buttons by their names; a dimmed one is read as
disabled. What's happening isn't announced as it changes: the phone is speaking the game and listening. A press that
can't reach the phone is announced as it appears.

The app supports ambient mode (`AmbientLifecycleObserver`): with the wrist down the screen stays on the game, black, with
the big button outlined, and the buzzes still come, which is when a player relying on them needs them.

The identifiers (test tags, readable as resource ids by UI Automator) are iOS's: `watch-title`, `watch-state`,
`watch-primary`, `watch-pause`, `watch-end-hint`, `watch-no-game` and `watch-trouble`.

## Building and testing

From `android/`:

```
.\gradlew.bat :wear:assembleDebug :app:assembleDebug
.\gradlew.bat :wear:link:test :wear:testDebugUnitTest :app:testDebugUnitTest
```

`:wear:testDebugUnitTest` runs the screen under Robolectric, on a large (454 px) and a small (384 px) round watch. With
`-PwearShots=<folder>` it also saves a square picture of each state there (`large-listening.png` and so on). They're
drawn on the computer (Robolectric's fonts, not the watch's), to look over, not for the store.

The watch app's applicationId is the phone app's, `com.epicaudiogames.app`, and both are signed with the same key (the
debug key in debug builds, Play's app signing key from Play), as the Data Layer requires. Its versionCode is the phone's
plus one, and its versionName the phone's (`android/wear/build.gradle.kts` reads them from the phone app's).

## On a Wear OS emulator

You need a Wear OS system image (Android Studio › SDK Manager › SDK Platforms, show package details: "Wear OS 5 Intel
x86_64 Atom System Image", API 34, or Wear OS 6, API 36), then a Wear OS AVD (Device Manager › Create virtual device ›
Wear OS › Wear OS Large Round). For the watch to reach a phone, pair it with a phone emulator that has Google Play:
Device Manager › the watch's ⋮ › Pair Wearable. The assistant installs the Wear OS companion on the phone and pairs
them.

1. Install both debug builds (`adb devices` lists their serials):

   ```
   adb -s <phone> install -r -t app\build\outputs\apk\debug\app-debug.apk
   adb -s <watch> install -r -t wear\build\outputs\apk\debug\wear-debug.apk
   ```

2. Start the phone app with the answers scripted (an emulator's microphone is no help), and the microphone not
   opening by itself, so that the watch's Talk opens it:

   ```
   adb -s <phone> shell am start -S -W -n com.epicaudiogames.app/.MainActivity --ez EpicNoIntro true --ez EpicSkipOnboarding true --es EpicAnalytics off --es EpicHear "yes|yes|yes|yes"
   ```

   Then Settings › Microphone › Open the microphone by itself: Never.
3. Open "Epic Audio Games" on the watch, and check:
   - With no game open, the watch says "Open a game on your phone".
   - Open Noodle Rush on the phone. The watch shows "Noodle Rush", "Speaking" and a **Skip** button.
   - **Skip** stops the voice on the phone. The watch shows "Your turn" and **Talk**.
   - **Talk** opens the microphone on the phone, with its listening sound. The watch shows "Listening…" and **Stop
     listening**. A moment later the scripted listener answers, and the game speaks again.
   - **Pause** shows the phone's Paused overlay. The watch shows "Paused" and **Carry on**, and Pause goes. **Carry
     on** asks the question again.
   - At a chapter's end the watch shows "Chapter complete" and "Choose what's next on your phone.", with no big
     button.
   - Back to games on the phone: "Open a game on your phone" again.
   - Force-stop the phone app (`adb -s <phone> shell am force-stop com.epicaudiogames.app`) with a game open, then
     press a watch button. The phone app starts in the background, and the watch says to open a game.
   - `adb -s <phone> logcat -s WearBridge` shows each press (`noodle-rush: watch -> SKIP`).

   An emulator's buzzes can't be felt; check those on a real watch.
4. Screenshots for Play (debug build): show a game's state without a phone, then save the watch's screen.

   ```
   adb -s <watch> shell am start -S -W -n com.epicaudiogames.app/com.epicaudiogames.wear.WatchActivity --es EpicWatchDemo listening
   adb -s <watch> exec-out screencap -p > watch-listening.png
   ```

   The states are `speaking`, `turn`, `listening`, `paused`, `wait`, `refused` (the microphone off), `end` and `none`,
   iOS's `-EpicWatchDemo` ones. Play wants Wear OS screenshots square (1:1), at least 384 x 384, of the app alone: no
   device frame, no circle mask, no transparency. A round emulator's screenshot is the right shape as it comes. They go
   in `android/fastlane/metadata/android/en-US/images/wearScreenshots/`.

## On a real watch

Turn on the watch's developer options (Settings › System › About › Versions: tap Build number seven times), then
Developer options › ADB debugging and Wireless debugging, and connect with `adb pair` / `adb connect` as it shows. Or
install from a Play testing track (Shipping). The phone needs the phone app from the same signer: both debug builds
from this computer, or both from Play.

Before the watch app is mentioned in the listing, check all of these on a real Wear OS watch paired with a real phone:

- **Install.** From Play, the watch app shows on the watch's Play Store under apps on your phone (the help topic "Using
  a watch" says to open the Play Store on the watch). Its name is "Epic Audio Games", and the round icon shows the
  whole emblem.
- **Haptics.** The start and stop buzzes are strong enough to notice during a game and clearly different from each
  other. The start buzz comes with the phone's listening sound, not noticeably after it. Try it with the phone in a
  pocket and its screen off.
- **Wrist down.** With the screen dimmed (ambient), check that the buzzes still come, that the screen is black with
  the big button outlined, and that the state is right again as soon as the wrist comes up. Wear OS may go back to the
  watch face after a while; then the app no longer buzzes until it's opened again.
- **TalkBack on the watch.** The title is read as a heading, then the state, then each button by its name. A dimmed
  button is read as disabled. A failed press is announced.
- **Text.** At the largest font size nothing is cut short and the list scrolls, with the crown too.
- **Phone locked.** The game plays on in the pocket, and both watch buttons work.
- **Phone app not running.** A press starts it in the background, and the watch then says to open a game.
- **Phone out of reach** (Bluetooth off on the phone, and no Wi-Fi). A press buzzes three times, and the watch says
  "Can't reach your phone…". It clears once the phone is back.
- **Microphone not allowed** on the phone. The watch shows "Talk (the microphone is off)", dimmed.
- **Media controls.** The watch's own media controls still show the game alongside our app, and their pause and play
  act on the game.
- **Battery.** After an hour of play with the watch app open, check how much battery the watch used.

## Shipping it in the phone app's listing

The watch app goes in the same Play listing as the phone app (the same package), as Google recommends, on its own
Wear OS track. Once, in the Play Console:

1. **Test and release › Advanced settings › Form factors › Add form factor › Wear OS.** Add the Wear OS screenshots
   (above; at least one) and accept the Wear OS review policy. Google reviews Wear OS apps against its Wear OS app
   quality guidelines.
2. Releases for the watch app go on the dedicated Wear OS tracks (Form factors › Wear OS › Manage › Releases). Their
   API names start `wear:` (`wear:production`, and the testing tracks' ids as the Play Console lists them), which is
   what `fastlane supply --track` takes.

Each release:

1. Build the release bundle, signed with the upload key the same way the phone app's lane does it (Android Gradle
   Plugin's injected signing properties; `android/fastlane/README.md` › Keys):

   ```
   ./gradlew :wear:bundleRelease \
     -Pandroid.injected.signing.store.file="$EAG_UPLOAD_KEYSTORE" \
     -Pandroid.injected.signing.store.password="$EAG_UPLOAD_KEYSTORE_PASSWORD" \
     -Pandroid.injected.signing.key.alias="$EAG_UPLOAD_KEY_ALIAS" \
     -Pandroid.injected.signing.key.password="$EAG_UPLOAD_KEY_PASSWORD"
   ```

   It makes `android/wear/build/outputs/bundle/release/wear-release.aab`. Check it isn't signed with the debug key
   (`keytool -printcert -jarfile wear-release.aab` must not say `CN=Android Debug`).
2. Upload it to a Wear OS track, in the Play Console or with
   `fastlane supply --aab android/wear/build/outputs/bundle/release/wear-release.aab --track wear:<track> --json_key "$PLAY_JSON_KEY" --package_name com.epicaudiogames.app --skip_upload_metadata --skip_upload_images --skip_upload_screenshots`.
   The phone app's lanes (`android/fastlane/Fastfile`) don't build or upload the watch app yet.

**versionCode.** Google takes each versionCode once across the whole listing, whatever the device. The watch app's is
the phone app's plus one (3 and 4 now). So the phone app's next release has to be at least two higher than its last
(5, then the watch's 6), which the phone lane's check of every track's versionCodes already asks for: it refuses a
versionCode that isn't higher than every one Google has, the watch's included. (Google suggests a separate scheme for
watch builds, such as a large prefix; that would need that check to leave the `wear:` tracks out.)

**Data safety.** No change. The watch app collects nothing and sends nothing to our server. The phone sends the watch
only the open game's title, the state's words, the button's name and two yes/no values, and the watch sends back
"primary" or "pause": none of it is personal data. It goes phone to watch through Google Play services, over
Bluetooth, or through Google's servers end-to-end encrypted when the watch isn't near the phone, and only the same app,
signed with the same key, on the user's own devices can read it. The phone app's existing answers already cover
everything the app collects (docs/STORE_LISTING.md).

## Differences from the Apple Watch app

For docs/IOS_PARITY.md. The same: the words, the button's names and icons by action, the dimmed button with the
microphone not allowed (and before the question), "Listening…", the end's heading and line, Pause hidden when it can't
pause, no buzz on the first state or as the game closes, the failure line, the identifiers and the demo states.

- **Catching up.** Coming back to its screen, the Wear OS app takes the phone's latest state without a buzz. The Apple
  Watch app's inbox has no such case: a change it missed while away can buzz as the watch hears again.
- **Contrast.** The Apple Watch app switches to the High contrast palette when the watch asks for more contrast. Wear
  OS has no such setting for apps to read, so the watch app keeps the Dark palette (every text pair 7:1 already).
- **Gestures.** The Apple Watch app's big button also answers Magic Tap and the double-tap gesture. Wear OS has neither
  for apps: the big button is pressed by touch, or with TalkBack's double tap.
- **Ambient.** Both draw the big button outlined; the Wear OS app's background is black then, too.
- **The phone app not running.** The iPhone app is launched in the background by the message, and finds no game open.
  On Android, the message starts the app's process (the `WearCommands` service), which tells the watch no game is open
  without opening the app's screen.
- **At an end,** a press that crosses with the end does nothing on Android (`WearBridge.perform`); iOS passes it to
  Magic Tap, which does nothing there either.
