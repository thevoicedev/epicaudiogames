# Releasing to the test tracks

The accessibility release (`docs/DESIGN.md`) goes to testers first, with the new listings, art and privacy answers
uploaded alongside:

- **Google Play's internal testing:** the phone and tablet app (versionCode 3), and the Wear OS app (versionCode 4) on
  the Wear OS form factor's own internal track (`docs/WEAR_OS.md`).
- **TestFlight's internal testers:** the iPhone and iPad app, with the Apple Watch app inside it (`docs/WATCH.md`).

Production review comes later, after the checks on real phones at the end of `docs/DESIGN.md` and on real watches
(`docs/WATCH.md`, `docs/WEAR_OS.md`), and the sign-in work.

It runs on three machines, in this order:

1. **This PC** (Windows): the checks, the Android builds and their tests, the emulator screenshots, Play's preview video,
   the store art.
2. **Railway** (driven from this PC): the website with the privacy policy's usage-data section, the usage-data API
   and its Postgres database. **The privacy policy goes live before any build with usage data reaches a tester.**
3. **The Mac**: the Apple Watch target (once), the iPhone and iPad app's tests, screenshots, App Preview and TestFlight
   build, then the signed Android uploads (the upload keystore, the Play service account key and the App Store
   Connect API key are only there).

The owner approves before anything ships: the sting, the earcons, the icon, the screenshot captions and feature
graphic, the preview video (gates 1 to 5), and finally the test builds on real phones (gate 6).

Each tool's `--help` is the last word on its options (`py -3.13 tools/<tool>.py <command> --help`); the commands
below were checked against them on 10 October 2026.

## Before starting, on both machines

- A clean tree, pulled: `git status` shows nothing, `git pull` is up to date.
- The versions: `versionCode = 3` and `versionName = "1.0"` in `android/app/build.gradle.kts`; the Wear OS app's
  versionCode is the phone app's plus one (4), and its versionName the same (`android/wear/build.gradle.kts` reads
  them); `MARKETING_VERSION = 1.0` in `ios/Config/Base.xcconfig`, which the watch app shares. Google takes each
  versionCode once across the whole listing, whatever the track or the device (2 is on internal testing already).
- The release notes: `android/fastlane/metadata/android/en-US/changelogs/3.txt` (the phone app),
  `changelogs/4.txt` (the Wear OS app) and `ios/fastlane/testflight/what_to_test.txt`.
- The packs haven't changed since they went to R2 (so `games/catalog.json`'s checksums still match the zips there):

  ```
  git log --oneline cee813cd..HEAD -- games/catalog.json games/*/packs      # prints nothing
  ```

- No machine points a release build at another pack server: `EPIC_PACKS_URL` isn't in `ios/Config/Local.xcconfig`,
  and `epicPacksUrl` is in neither `~/.gradle/gradle.properties` nor the environment (`check_packs.py` and both
  fastlane `check` lanes say which address each build gets).

## 1. This PC (Windows, PowerShell, from the repo root)

Python is `py -3.13` here. The emulator is `%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe`, AVD
`EpicAudioGames_Pixel`. The engine and `games/` don't change in this release, so the engine fixtures stay as they
are (if they ever need regenerating here, check the LF checkout first: `git ls-files --eol games` shows `w/lf`).

**Checks** (each exits non-zero on a problem):

```
py -3.13 tools/validate.py                 # every map and clip
py -3.13 tools/app_audio.py check          # content/app/app.json matches app_text.toml and the picks
py -3.13 tools/check_store.py              # both listings, the privacy answers, the icon, screenshots, previews
py -3.13 tools/check_packs.py --sha        # the three zips on R2 against the catalog (downloads 174 MB, read-only)
npm install --prefix web
npm test --prefix web                      # the usage-data API, the privacy page's lists, the database code
```

**Android: tests and release builds.** The emulator in a window of its own (`-no-window` runs it headless):

```
Start-Process "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -ArgumentList "-avd EpicAudioGames_Pixel -no-snapshot-save"
adb wait-for-device
cd android
.\gradlew.bat :engine:test :app:testDebugUnitTest :wear:link:test :wear:testDebugUnitTest
.\gradlew.bat :app:connectedDebugAndroidTest              # about 200 screen tests, accessibility checks among them
.\gradlew.bat :app:assembleRelease :wear:assembleRelease  # signed with the debug key: for the smoke tests only
adb install -r app\build\outputs\apk\release\app-release.apk
cd ..
```

- The screen tests take 25 to 30 minutes, and uninstall the app at the end. On a busy PC the emulator's system can
  restart mid-run ("System has crashed"): run the classes that didn't finish again, quoted so PowerShell keeps the
  argument whole, for example `.\gradlew.bat :app:connectedDebugAndroidTest
  "-Pandroid.testInstrumentationRunnerArguments.class=com.epicaudiogames.app.AppSmokeTest"` (the tablet and 200%
  variants are classes of their own, `...TabletTest` and `...LargeTextTest`).
- `:wear:testDebugUnitTest` draws the watch's screen in every state under Robolectric; there's no Wear OS emulator here
  yet. `docs/WEAR_OS.md` says how to make one, and what to try on it.

Then a smoke test on the emulator with TalkBack on (Settings, Accessibility, TalkBack; or `adb shell settings put
secure enabled_accessibility_services
com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService` and `adb shell settings put
secure accessibility_enabled 1`, and `adb shell settings delete secure enabled_accessibility_services` to turn it off
again): the intro, the welcome, a game where the microphone waits instead of opening by itself, the Shop, Help and
Settings.

**Store art** (gates 3 and 4; `docs/STORE_ART.md`). The owner's icon (icon-03) and the feature graphic (feature-02)
are exported already; these say nothing has drifted:

```
py -3.13 tools/make_art.py export all --check   # every icon, Play's icon and feature graphic, the website's images
py -3.13 tools/make_art.py check
```

**Play's screenshots.** Eight each for phones, 7-inch and 10-inch tablets were made on 10 October 2026 (the 10-inch
set half upright, half sideways). Make them again only if the screens changed; the debug build has to be on the
emulator:

```
.\android\gradlew.bat -p android :app:installDebug
py -3.13 tools/store_shots.py android      # every scene for phone, tablet7, tablet10 and tablet10-land -> build/store-shots/android/raw/
py -3.13 tools/make_art.py shots android --sizes phone,7in,10in,10in-land --replace
py -3.13 tools/store_shots.py check        # every framed shot against the stores' rules
py -3.13 tools/make_art.py sheet shots     # build/art/review/shots.html, for gate 4
```

Look at every capture: the status bar at 9:41, and nothing over the app. Two things went wrong on a busy PC on
10 October:

- An "isn't responding" dialog covered the captures. Before the run, `adb shell settings put global
  hide_error_dialogs 1`; afterwards, `adb shell settings delete global hide_error_dialogs`.
- `05_voice_speed` sets a larger font, which restarts the status bar out of its demo mode, so it and the scenes after
  it showed the real time. Take it in a run of its own, with the font set first: the other scenes with `--only
  01_games,02_story,03_answer,04_big_text,06_help,07_shop,08_eight_games`, then `adb shell settings put system
  font_scale 1.3`, `--only 05_voice_speed`, and `adb shell settings put system font_scale 1.0`.

**Wear OS screenshots.** Play wants at least one before the Wear OS app can go on its track, and there are none yet:
they need a Wear OS emulator (`docs/WEAR_OS.md`, On a Wear OS emulator) next to the phone's. With both running (`adb
devices` lists their serials) and the debug builds installed (the phone app on the phone emulator,
`android\wear\build\outputs\apk\debug\wear-debug.apk` on the watch's: `adb -s <watch serial> install -r -t ...`):

```
py -3.13 tools/store_shots.py android --targets wear --wear <watch serial> --serial <phone serial>
py -3.13 tools/make_art.py shots android --sizes wear     # -> images/wearScreenshots/: square, no caption, no frame
```

**Play's preview video** (gate 5), from the emulator. A cut made on 10 October (29 s, 1080 x 1920) is in
`build/preview/play/` (not in git), with its `.srt`; to make it again:

```
py -3.13 tools/make_preview.py capture-android                  # the takes in brand/previews/storyboard.json
py -3.13 tools/make_preview.py plan                             # where each take's sounds fall: set brand/previews/play.json's in and out points from it
py -3.13 tools/make_preview.py edit brand/previews/play.json     # -> build/preview/play/epic-audio-games-preview.mp4 and .srt
py -3.13 tools/make_preview.py check build/preview/play/epic-audio-games-preview.mp4
```

On a busy PC, check the cut's picture against its sound at each scene change: `adb screenrecord`'s timeline drifted
under load on 10 October. The owner puts the cut on YouTube (portrait is fine; public or unlisted, ads off, embedding
allowed, the `.srt` as its captions), and its address goes into Play's listing, with no newline:

```
Set-Content -NoNewline -Path android\fastlane\metadata\android\en-US\video.txt -Value "https://www.youtube.com/watch?v=<id>"
```

The App Store's preview has to show the iPhone app, so it's made on the Mac (section 3).

**Then check again, and hand over:**

```
py -3.13 tools/check_store.py
git status                          # look before committing: no keys, nothing from build/
```

Commit and push only once the owner says so; the Mac pulls from there.

## 2. Railway (from this PC)

The project is `epicaudiogames.com`, environment `production`, service `web` (us-east4); the repo root is linked to
it (`railway status` says so; `railway link` if not). The database is new and costs a little each month: the owner
approves it first.

**Once: the database.**

```
railway add --database postgres
railway variable set 'DATABASE_URL=${{Postgres.DATABASE_URL}}' --service web --skip-deploys
```

In the dashboard, check the Postgres service runs in the same region as `web` (US East). The server makes its table
and indexes itself on start.

**Deploy, then check** (`web/node_modules/` stays behind; Railway installs from `web/package-lock.json`):

```
railway up web --path-as-root --service web
curl.exe -sI https://epicaudiogames.com/privacy          # 200
curl.exe -sI https://epicaudiogames.com/support          # 200
curl.exe -sI https://epicaudiogames.com/accessibility    # 200
node web/scripts/smoke.js https://epicaudiogames.com     # 405, 415, 400, 202 (with the apps' user agent), forget 202, 429
railway run --service Postgres node web/scripts/db-check.js 00000000-0000-4000-8000-000000000001
railway logs --service web --lines 100                   # no IP addresses, no request bodies
```

- `smoke.js` sends its events under the reserved install `00000000-0000-4000-8000-000000000001`, which every report
  leaves out, and forgets them again; `db-check.js` then shows the table's columns (no IP address among them) and 0
  rows for it.
- If the apps' user agent gets a 403 from Cloudflare (Bot Fight Mode challenges it), add a WAF skip rule for
  `epicaudiogames.com/api/*` in the Cloudflare dashboard, and run `smoke.js` again.
- Reports: `railway run --service Postgres py -3.13 tools/analytics_report.py` (once `py -3.13 -m pip install
  "psycopg[binary]"`), or `py -3.13 tools/analytics_report.py --sql` and paste it into the Postgres service's Data tab
  (Query). The views are `report_events`, `report_funnel`, `report_games`, `report_chapter_ends`, `report_drop_off`,
  `report_shop`, `report_retention` and `report_devices` (`web/analytics/views.sql`).

## 3. The Mac: the iPhone, iPad and Apple Watch apps

Needs Xcode 26 (App Store Connect only takes its builds) with the watchOS and visionOS simulators (Xcode, Settings,
Components), fastlane 2.232.2 or later (2.233.0 or later for the previews lane: `brew upgrade fastlane`), ffmpeg
(`brew install ffmpeg`), and the API key in the environment (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`:
`ios/fastlane/README.md`). The art and preview tools run in their own Python, pinned so the Mac's files match this
PC's (`docs/STORE_ART.md`):

```
python3 -m venv .venv-art && .venv-art/bin/pip install -r tools/requirements-art.txt
```

**Once: the Apple Watch target.** Xcode makes it, from our `ios/EpicWatch/` folder: follow `docs/WATCH.md`, Adding the
watch target (15 steps, with checks of the resolved settings and the built Info.plist). Then commit
`ios/EpicAudioGames.xcodeproj/project.pbxproj` and the shared `EpicWatch` scheme, once the owner says so. The iPhone
app's build then makes the watch app and embeds it; `fastlane ios beta` needs no change. Don't skip it: the Help
topic "Using a watch" and What to Test describe the watch app (the topic's paragraphs about it would have to come out
of `tools/app_text.toml` for a build without it).

**Checks and tests:**

```
git pull
grep EPIC_PACKS_URL ios/Config/Local.xcconfig        # prints nothing (Base.xcconfig has the R2 address)
python3 tools/check_store.py
python3 tools/check_packs.py
swift test --package-path ios/EpicEngine             # the engine, the app's core and the watch's messages
xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -derivedDataPath ios/build test
xcodebuild -project ios/EpicAudioGames.xcodeproj -scheme EpicWatch \
  -destination 'generic/platform=watchOS Simulator' build
```

The first `xcodebuild` is the app's unit tests and UI tests, Apple's accessibility audit among them, with the real
`content/`, on an iPhone and an iPad. Then by hand:

- the watch app on a paired simulator (`docs/WATCH.md`, Testing with a paired simulator);
- the app on My Mac (Designed for iPad) and on the visionOS simulator: window sizes, the keyboard, the pointer, the
  microphone (`docs/IOS.md`, iPad, Mac and Vision). App Store Connect offers an iPad app on both by default: turn off
  either one that isn't right (below).

**Screenshots** (each simulator set up as the top of `ios/EpicAudioGamesUITests/StoreScreenshotsUITests.swift` says:
English (U.S.), the status bar at 9:41). One run on each simulator; the iPad's land in `raw/ipad13/`:

```
mkdir -p build/store-shots/ios/raw
for device in 'iPhone 17 Pro Max' 'iPad Pro 13-inch (M4)'; do
  TEST_RUNNER_EPIC_STORE_SHOTS=$PWD/build/store-shots/ios/raw xcodebuild \
    -project ios/EpicAudioGames.xcodeproj -scheme EpicAudioGames \
    -destination "platform=iOS Simulator,name=$device" \
    -only-testing:EpicAudioGamesUITests/StoreScreenshotsUITests test
done
.venv-art/bin/python tools/make_art.py shots ios --sizes 6.9,6.3,13 --replace   # -> ios/fastlane/screenshots/en-US/
.venv-art/bin/python tools/make_art.py sheet shots                              # for gate 4
```

- `--replace` takes the old screenshots (the old design's) out of the folder, which `fastlane ios screenshots`
  uploads whole: 8 at 6.9" (1320 x 2868), 8 at 6.3" (1206 x 2622) and 8 for the 13" iPad (2064 x 2752).
- The iPhone run also takes each pack's row in the Shop, `iap_<product id>.png`, which `shots` copies unframed to
  `ios/fastlane/iap_review/<product id>.png`. Its price must show ("Buy for £1.99", from
  `ios/Config/EpicAudioGames.storekit`): if the test says there's no price from the App Store, add the StoreKit
  configuration to the scheme's Test options.
- Apple Watch screenshots aren't needed for TestFlight; App Review wants them once a build with the watch app is
  submitted (`docs/WATCH.md`, step 5 of Testing).

**The App Preview** (gate 5; not needed for TestFlight), from an iPhone simulator, with its sound through BlackHole
(`brew install blackhole-2ch`, then Simulator, I/O, Audio Output, BlackHole 2ch):

```
.venv-art/bin/python tools/make_preview.py capture-ios            # the takes, on the booted simulator
.venv-art/bin/python tools/make_preview.py plan                   # set brand/previews/appstore.json's in and out points from it
.venv-art/bin/python tools/make_preview.py edit brand/previews/appstore.json --install   # -> ios/fastlane/app_previews/en-US/01_IPHONE_67.mp4
.venv-art/bin/python tools/make_preview.py check ios/fastlane/app_previews/en-US/01_IPHONE_67.mp4
```

**fastlane**, from `ios/`:

```
fastlane ios check
fastlane ios beta dry_run:true       # Packs URL https://packs.epicaudiogames.com; What to Test from testflight/
fastlane ios beta                    # builds the app (the watch app inside), signs, uploads to TestFlight (internal testers)
fastlane ios metadata                # the listing, review notes, age rating, price
fastlane ios screenshots             # the iPhone and iPad sets
fastlane ios previews                # or add the video on the version's page if fastlane is older than 2.233.0
fastlane ios iap_review_screenshots
FASTLANE_USER=james@hugo.fm fastlane ios privacy     # App Privacy: asks for the password and a 2FA code
```

`fastlane ios check` insists on the iPhone sets only: look in `ios/fastlane/screenshots/en-US/` for the iPad's too,
since App Store Connect wants them before the app goes to App Review.

On the App Store Connect website:

- App Privacy's Privacy Choices URL: `https://epicaudiogames.com/privacy#usage-data`.
- TestFlight: the internal group with its testers; check the build shows What to Test.
- Pricing and Availability: "iPhone and iPad Apps on Apple Silicon Macs" and Apple Vision Pro. Both are on for an iPad
  app unless turned off; leave each on only once the check above passed.

## 4. The Mac: the Android apps

Needs JDK 17, `android/local.properties` (the SDK's path), and the keys in the environment (`PLAY_JSON_KEY`,
`EAG_UPLOAD_KEYSTORE` and its passwords from the Keychain: `android/fastlane/README.md`). From `android/`:

```
fastlane android check
fastlane android internal        # builds versionCode 3, signs it with the upload key, uploads it with changelogs/3.txt
fastlane android metadata        # the texts, the video's address, the icon, feature graphic, and every screenshot
                                 #   folder: phone, 7- and 10-inch tablets, and Wear OS once it has some
fastlane android iaps            # only if the three packs aren't on Google Play yet (safe to run again)
```

**The Wear OS app** goes in the same listing, on the Wear OS form factor's own tracks (`docs/WEAR_OS.md`, Shipping it
in the phone app's listing).
Once, in the Play Console: Test and release, Advanced settings, Form factors, Add form factor, Wear OS; give it the
Wear OS screenshots (section 1) and accept the Wear OS review policy. Then, from `android/`, the bundle signed with the
upload key, and up to the Wear OS internal track with `changelogs/4.txt` as its notes:

```
./gradlew :wear:bundleRelease \
  -Pandroid.injected.signing.store.file="$EAG_UPLOAD_KEYSTORE" \
  -Pandroid.injected.signing.store.password="$EAG_UPLOAD_KEYSTORE_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$EAG_UPLOAD_KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$EAG_UPLOAD_KEY_PASSWORD"
keytool -printcert -jarfile wear/build/outputs/bundle/release/wear-release.aab   # not "CN=Android Debug"
fastlane supply --aab wear/build/outputs/bundle/release/wear-release.aab --track wear:internal \
  --json_key "$PLAY_JSON_KEY" --package_name com.epicaudiogames.app --metadata_path fastlane/metadata/android \
  --skip_upload_metadata --skip_upload_images --skip_upload_screenshots
```

`wear:internal` is the Wear OS internal testing track's id as the Play Console's API names it: check it there the first
time (Form factors, Wear OS, Manage). Or upload the bundle on that track's page and paste `changelogs/4.txt` as its
release notes. The phone app's lanes don't build or upload the watch app. If `fastlane android metadata` refuses the
Wear OS screenshots before the form factor is added, add it first (with the same screenshots, by hand) and run the
lane again.

In the Play Console: **Data safety** (Policy and programs, App content) with the answers in
`docs/STORE_LISTING.md`, before the build goes to testers (the watch app changes nothing there); licence testers
(Setup, License testing) for sandbox purchases; the internal testers' list, on the phone app's track and on the Wear
OS one.

## 5. Testers, and the last gate

- TestFlight: the internal group gets the build once Apple has processed it, on iPhone and iPad (and on an
  Apple-silicon Mac); the watch app installs from the Watch app on the iPhone. Google Play: the internal testing list
  gets it within minutes; its testers need the opt-in link from the track's page, and the watch app comes from the
  Play Store on the watch once they're testers on the Wear OS track too.
- **Gate 6:** the owner tests on real devices with the checklists: the end of `docs/DESIGN.md` (a whole game with
  VoiceOver and with TalkBack, the microphone, the listening sounds over Bluetooth, voice speed, the largest text, a
  tablet and an iPad, a sandbox purchase, download and restore on both stores, and usage data arriving, stopping when
  it's switched off, and gone after "Delete my usage data": `db-check.js` with the tester's install ID, or the
  reports), and the real-watch checks in `docs/WATCH.md` and `docs/WEAR_OS.md`.
- Play's pre-launch report (Release, Testing, Pre-launch report), when Google has run it: its accessibility findings
  go to the next build.
- Only after gate 6 do the listings claim VoiceOver or TalkBack, or mention the watch apps (`docs/STORE_LISTING.md`),
  and the production submission declares Apple's accessibility labels.

## If something stops

- **A lane says the pack server isn't R2:** take `EPIC_PACKS_URL` out of `ios/Config/Local.xcconfig`, or
  `epicPacksUrl` out of `~/.gradle/gradle.properties` (or unset `ORG_GRADLE_PROJECT_epicPacksUrl`). The R2 address
  is already in `Base.xcconfig` and `android/gradle.properties`.
- **"versionCode 3 isn't new":** Google has it already (any track, even unreleased). Raise the phone app's
  `versionCode` by two, to 5, since the Wear OS app takes the next one (6), and rename the release notes to match:
  `changelogs/3.txt` to `5.txt` and `4.txt` to `6.txt`. Raising it by one would make the phone app 4, and its upload
  would carry the watch app's notes.
- **`fastlane ios beta` can't sign the watch app:** the watch target needs automatic signing with the same team
  (`docs/WATCH.md`, step 11); the lane's `-allowProvisioningUpdates` registers its App ID
  (`com.epicaudiogames.app.watchkitapp`).
- **`fastlane ios check` says the privacy manifest and the App Privacy answers differ:** `PrivacyInfo.xcprivacy`'s
  collected data types and `app_privacy_details.json` have to list the same four (`docs/STORE_LISTING.md`).
- **`check_store.py` says the privacy policy doesn't list an event:** every event in `web/analytics/events.json`
  needs its `<li data-event="...">` in `web/public/privacy.html`'s usage-data section; deploy the site again.
- **The smoke test's rows are still there:** `node web/scripts/smoke.js https://epicaudiogames.com` forgets them
  at the end; `curl.exe -s -X POST -H "Content-Type: application/json" --data "@web/test/smoke-forget.json"
  https://epicaudiogames.com/api/forget` does it alone.
