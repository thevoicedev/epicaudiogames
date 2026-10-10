# Store listings

The words for both stores live in the repo as plain text files, laid out for fastlane: `fastlane deliver` reads
`ios/fastlane/`, `fastlane supply` reads `android/fastlane/`. Those files are the source of truth. This page says
where each field lives, and gives the answers for the forms only the App Store Connect and Play Console websites can
fill in. The app exists in both: App Store Connect (app id 6820105215, with the three in-app purchases) and the Play
Console (HUGO.FM GAMES LIMITED, versionCode 2 on internal testing since 7 October 2026). The texts here are the
accessibility release's (versionCode 3, the Wear OS app's versionCode 4, and the next TestFlight build, with the iPad
and the Apple Watch app) and haven't been uploaded yet: `docs/RELEASE.md` has the order. `tools/check_store.py`
checks every file below against both stores' rules, offline.

The public pages the listings link to are on the website: `web/public/privacy.html` (epicaudiogames.com/privacy),
`web/public/support.html` (epicaudiogames.com/support) and the accessibility statement
(epicaudiogames.com/accessibility).

## The facts the copy rests on

Checked on 10 October 2026 against `docs/DESIGN.md`, which both apps are built to, and the apps themselves. If one of
these changes, the listings, the privacy policy and the answers below change with it.

- **Devices:** the iPhone app is also the iPad app (`TARGETED_DEVICE_FAMILY = 1,2`, iOS and iPadOS 17 or later), and
  runs on Apple-silicon Macs and Apple Vision Pro as "Designed for iPad" (`ios/Config/App.xcconfig`); the Android app
  runs on phones (Android 7 or later), tablets, foldables and Chromebooks. On a tablet or an iPad it turns any way,
  takes any window size, lays a game out in two panes when there's room, and takes a keyboard (Space, Escape, the
  tab shortcuts). The listings say "Plays on iPhone and iPad" and "Plays on phones and tablets" (not "Made for
  iPhone", which is Apple's badge for accessories); neither names the Mac, Vision Pro or Chromebooks, which nobody
  has tried yet.
- **Watches:** a watch's own Now Playing or media controls work with any game (the help topic "Using a watch"). The
  watch apps, a remote for the game on the phone (`docs/WATCH.md`, `docs/WEAR_OS.md`), are built: the Apple Watch app
  goes inside the iPhone app once its Xcode target is added, and the Wear OS app is a bundle of its own for Play's
  Wear OS tracks. Until each passes its real-watch checks, the listings don't mention them; TestFlight's What to
  Test, the App Review notes and the Wear OS build's release notes (`changelogs/4.txt`) do, for the testers and
  reviewers who get them.
- **Answering:** speak, type, or tap one of the question's options, shown as buttons at the end of the chat. Every
  word is shown as it's spoken, the word being spoken highlighted. The mic opens by itself after each question, with
  a short sound, except with a screen reader on (Settings, "Open the microphone by itself": not when a screen reader
  is on, the default; always; never). The listings say "When it's your turn, say your answer, type it, or tap an
  option".
- **Made for blind and partially sighted players first:** Atkinson Hyperlegible text (or the phone's font) in three
  sizes on top of the phone's own, dark, light and high-contrast themes, voice speed (0.75 to 2 times), music
  volume, more time to answer, listening sounds, and help topics read aloud. What the listings may not say yet:
  "Works with VoiceOver" or "Works with TalkBack", until the checks on real phones at the end of `docs/DESIGN.md`
  pass.
- **Speech:** iOS uses `SFSpeechRecognizer`, on the device where the iPhone supports it and otherwise on Apple's
  servers (`SpeechListener.swift`). Android uses the phone's `SpeechRecognizer`, which is usually Google's: offline
  where the phone has English, else online (`Listener.kt`). The app never records audio or sends it to us.
- **Network:** the apps make three kinds of request: pack downloads from the R2 bucket, packs.epicaudiogames.com
  (`Store.kt`, `PackDownloader.swift`); the stores' own purchase calls (Play Billing, StoreKit 2); and the usage data,
  to epicaudiogames.com/api/events (and /api/forget). No web views. Settings, "Help and about", has the privacy
  policy, support and the accessibility statement, which open in the phone's browser: both stores want the privacy
  policy reachable inside the app.
- **The watch link:** the phone tells its own watch the open game's title, what it's doing in words, the big button's
  name and two yes/no values (listening, can pause), and the watch sends back "primary" or "pause". Nothing else, and
  none of it goes to us or holds anything about the player. On iOS it's WatchConnectivity, device to device; on
  Android, Google Play services' Data Layer, over Bluetooth, or through Google's servers end-to-end encrypted when
  the watch is away from the phone, readable only by the same app, signed with the same key, on the player's own
  devices. The watch apps collect nothing (the Apple Watch app's `PrivacyInfo.xcprivacy` says so).
- **Usage data** (first-party analytics): a random ID made on the phone's first launch (kept in the app's own files,
  not backed up, new after a reinstall, forgotten when sharing is turned off), and the events in
  `web/analytics/events.json`: which tabs and games are opened, how far games get, purchases and their results, pack
  downloads, a game's errors, and with each event the app's version, the system (iOS or Android) and its version, the
  language, and the kind of device (phone, tablet, computer or watch). Never what the player says or types, the transcript, audio, whether a
  screen reader is on, any accessibility or comfort setting, which help topic was read, the device's make or model,
  advertising IDs or location. On by default; the welcome says so with a "Turn off" button, and Settings, Privacy,
  has "Share usage data" and "Delete my usage data". It goes to our own server (Railway, in the US, with Cloudflare
  in front) and is kept 13 months. The server uses IP addresses only in memory, for rate limiting (Cloudflare's and
  Railway's standard request logs keep them briefly). It's pseudonymous, not anonymous: no text calls it anonymous.
- **No third-party SDKs:** AndroidX, Media3, Compose, Play Billing and Google Play services' Wearable API (the watch
  link, in the phone app and the Wear OS app) on Android, and Apple's frameworks on iOS: no ads, and no third-party
  analytics, crash reporting or tracking. `PrivacyInfo.xcprivacy` declares no tracking, the
  collected data types under "App Store Connect: App Privacy" below, and the required-reason APIs the Release code
  calls: free disk space (E174.1, before a pack downloads), `mach_absolute_time` (System Boot Time, 35F9.1: the mic
  level meter and the audio graph's timing) and UserDefaults (CA92.1: the settings). `fastlane ios check` fails if
  the code starts using another one undeclared, or if the collected data types and the App Privacy answers differ.
- **Saves and settings** are on the device (SharedPreferences on Android, Application Support and UserDefaults on
  iOS). They hold the game's place and variables and the player's settings, not what the player said. Both go into
  the device's own backups (Android's backup rules take exactly those two files; iOS backs up Application Support
  and UserDefaults), so a new phone keeps the games' places and the settings, "Share usage data" off included; the
  usage data's ID and queue never do. Packs are left out of both.
- **Offline:** every game ships inside the app. Buying and downloading packs needs a connection, and so does speech
  on devices that can't recognise English on the device. Usage data waits on the phone until there's one.

## App Store: where each field lives

All under `ios/fastlane/`. `metadata/` is the `deliver` metadata folder; `en-US` is the primary language.

| Field | File | Limit | Now |
|---|---|---|---|
| Name | `metadata/en-US/name.txt` | 30 | 16 |
| Subtitle | `metadata/en-US/subtitle.txt` | 30 | 29 |
| Keywords | `metadata/en-US/keywords.txt` | 100 bytes | 97 |
| Promotional text | `metadata/en-US/promotional_text.txt` | 170 | 155 |
| Description | `metadata/en-US/description.txt` | 4000 | 3573 |
| What's New | none: version 1.0 has no release notes. Add `release_notes.txt` from 1.1 | 4000 | |
| TestFlight's What to Test | `testflight/what_to_test.txt` (`fastlane ios beta` sends it) | 4000 bytes | 2484 |
| Screenshots | `screenshots/en-US/<name>_<width>x<height>.png` (`fastlane ios screenshots`): iPhone 6.9" 1320 x 2868 and 6.3" 1206 x 2622, iPad 13" 2064 x 2752, made by `make_art.py shots ios` (`docs/STORE_ART.md`); Apple Watch ones once a build with the watch app goes to App Review | 10 per size | the old design's 6.9" set, until the Mac's run |
| App Previews | `app_previews/en-US/<n>_IPHONE_67.mp4` (`fastlane ios previews`) | 3 per size, 15 to 30 s | none yet |
| Marketing URL | `metadata/en-US/marketing_url.txt` | | https://epicaudiogames.com/ |
| Support URL | `metadata/en-US/support_url.txt` | | https://epicaudiogames.com/support |
| Privacy policy URL | `metadata/en-US/privacy_url.txt` | | https://epicaudiogames.com/privacy |
| Copyright | `metadata/copyright.txt` | | 2026 Hugo FM (your choice; the legal name would be "2026 Hugo.FM Games Limited") |
| Categories | `metadata/primary_category.txt` and the `*_sub_category.txt`, `secondary_category.txt` files | | see below |
| App Review contact | `metadata/review_information/{first_name,last_name,phone_number,email_address}.txt` | | James Holland, james@hugo.fm, +447468595532 |
| App Review notes | `metadata/review_information/notes.txt` | 4000 | 3922 |
| App Review attachment | `metadata/review_information/attachment.*` (optional; see `ios/fastlane/README.md`) | | none yet |
| Age rating | `app_rating_config.json` (`deliver`'s `app_rating_config_path`) | | 13+ |
| App Privacy | `app_privacy_details.json` (`upload_app_privacy_details_to_app_store`) | | the usage data (below) |

The keywords leave out every word of the name and subtitle, since Apple indexes those already: blind, accessible,
low vision, interactive, adventure, mystery, werewolf, pirate, speak, talk, offline, quiz. The first three came with
the accessibility release, for players looking for games they can play; drama, trivia, alien and detective made room
for them. "radio" and "headphones" were dropped before: Apple rejects keywords that don't describe the app (2.3.7),
and "radio" mostly matches people looking for radio stations. "Audio game" and "audio drama" still match, since
Apple combines keywords with the name.

## Google Play: where each field lives

All under `android/fastlane/metadata/android/en-US/`, the `supply` layout.

| Field | File | Limit | Now |
|---|---|---|---|
| App name | `title.txt` | 30 | 16 |
| Short description | `short_description.txt` | 80 | 80 |
| Full description | `full_description.txt` | 4000 | 3568 |
| Release notes for versionCode 1 | `changelogs/1.txt` (one file per versionCode) | 500 | 169 |
| Release notes for versionCode 3, the accessibility release | `changelogs/3.txt` | 500 | 494 |
| Release notes for versionCode 4, the Wear OS app's first build | `changelogs/4.txt` (on its Wear OS track: `docs/RELEASE.md`) | 500 | 404 |
| Release notes for any other versionCode | `changelogs/default.txt` | 500 | 48 |
| Promo video | `video.txt`: the YouTube address (`https://www.youtube.com/watch?v=<id>`, public or unlisted, ads off), once Play's preview cut (1080 x 1920, portrait) is up | | none yet |
| Icon, feature graphic | `images/icon.png` (512 x 512), `images/featureGraphic.png` (1024 x 500), from `make_art.py export store` | | icon-03, feature-02 |
| Screenshots | `images/phoneScreenshots/`, `sevenInchScreenshots/`, `tenInchScreenshots/` (framed by `make_art.py shots android`), and `wearScreenshots/` (square, unframed) | 8 per kind | 8 phone (1080 x 1920), 8 7-inch (1080 x 1920), 8 10-inch (4 at 1440 x 2560, 4 sideways at 2560 x 1440); no Wear OS ones yet |

supply sends these files exactly as they are, without trimming, so a trailing newline counts towards the limit:
`short_description.txt` is exactly 80 characters ("Audio story games you play by voice. Big clear text, high
contrast, spoken help.") and must stay without one (`fastlane android check` and `tools/check_store.py` measure
what supply sends).

The release notes go by versionCode, and the Wear OS app's is always the phone app's plus one (3 and 4 now), so the
phone app's versionCodes go up two at a time (5 and 6 next): a phone build numbered 4 would carry the watch app's
notes.

Both descriptions open with who the games are designed for (blind and partially sighted players first) and what
makes them easy to play, then the eight games, the packs and "Good to know". They differ only where the platforms
do: speech is described as each platform does it, Family Sharing is mentioned only on the App Store, the devices are
"iPhone and iPad" or "phones and tablets" (with "your device" where both are meant), and the App Store text never
names Android, TalkBack, Google or Wear OS (Apple's guideline 2.3.10). With the usage data, "no account" and "no
tracking" came out of both (the data is collected under a random ID; "No ads" stays), and a plain sentence says
what's shared and that Settings turns it off.

Two claims wait for real devices:

- **Screen readers.** Neither listing claims VoiceOver or TalkBack until the checks on real phones at the end of
  `docs/DESIGN.md` pass. Then add a line like "Works with VoiceOver. Magic Tap skips the voice, starts listening, or
  carries on." to the App Store description and its TalkBack twin to Play's, and run `tools/check_store.py --claims
  voiceover,talkback` (without it, the check stops on them).
- **The watch apps.** Neither listing mentions them until their real-watch checks pass (`docs/WATCH.md`,
  `docs/WEAR_OS.md`). Then add a line to "Made to be easy to play" like "With an Apple Watch, the Epic Audio Games
  watch app shows what the game is doing, its big button skips, talks or carries on, and it buzzes when the
  microphone opens." (Play's: "With a Wear OS watch, …"), and the Apple Watch screenshots to the App Store.

## Categories

- **App Store:** primary **Games**, with the subcategories **Adventure** and **Puzzle**; secondary
  **Entertainment**. Five of the eight games are story adventures you steer (Frootopia, Noodle Rush, Signal Decoders,
  Pirate Quest, Alien Customs), and The Werewolf, Signal Decoders and Leaning Tower of Pizza are puzzles: who is the
  werewolf, decoding a signal, true or false. Entertainment is where people browse for radio plays and audio drama,
  which is what the games sound like. Not Kids, and not the Family subcategory, which would clash with a 13+ rating.
- **Google Play:** app type **Game**, category **Adventure**, for the same reason. Play allows one category. Add up
  to five tags in the console (Store settings), from its list: for example Interactive story, Mystery, Single
  player, Offline and Casual.

## Devices

- **App Store:** one app for iPhone and iPad (iOS and iPadOS 17 or later), with the Apple Watch app inside it
  (watchOS 10 or later), which installs from the Watch app on the iPhone and never on its own. App Store Connect also
  offers an iPad app to Apple-silicon Macs and Apple Vision Pro, as "Designed for iPad", unless Pricing and
  Availability says otherwise: keep each only once it's been tried there (`docs/RELEASE.md`). They show the iPad's
  screenshots. App Review wants the 13" iPad set before the app goes to review, and Apple Watch screenshots once a
  build with the watch app does; TestFlight wants neither.
- **Google Play:** phones and tablets share the listing and its tracks; tablets are shown the 7-inch and 10-inch
  screenshots. Wear OS is a form factor added once in the Play Console (Test and release, Advanced settings, Form
  factors), with its own tracks (`wear:internal`, `wear:production`, …), its own screenshots and Google's review
  against its Wear OS app quality guidelines; the watch app needs the phone app (`standalone="false"`).
- **Chromebooks:** Play offers the Android app to ChromeOS devices whose hardware its manifest allows. The manifest
  doesn't say a touchscreen is optional (`android.hardware.touchscreen`, `required="false"`), so Play keeps it from
  Chromebooks without one, although keyboard and mouse reach everything (`docs/DESIGN.md`). Declaring it optional,
  after a try on a Chromebook, would open those up.

## In-app products

The same three product ids on both stores, each a non-consumable (Play: one-time product) at $1.99, with the same
display names on both. On Google Play, `fastlane android iaps` sends exactly the names and descriptions below: they
are `PLAY_PRODUCTS` in `android/fastlane/Fastfile`, the one source (the descriptions are the packs' own, from
`games/catalog.json`, which the app's store sheet shows too). Change one there and here together.

| Product id | Display name (both stores) | Description (Play) |
|---|---|---|
| `frootopia_stories` | Frootopia: Stories 2 to 5 | The Stowaway, The Mould Moon, The Edge of Everything and The Last Star: the rest of Cosmo, Gribbo and Pip's adventure. |
| `alien_customs_levels` | Alien Customs: 10 More Levels | Levels 6 to 15, from a sports tournament to a business trip: 30 more items to talk past the officer, from marshmallows to rizz books. |
| `the_werewolf_stories` | The Werewolf: 45 Mysteries | Stories 6 to 50, from The Haunted Mill to The Cursed Well: 45 more villages, each with two werewolves hiding among the villagers. |

App Store: created, with Family Sharing on; their descriptions are already in App Store Connect. Google Play: the
`iaps` lane creates them, and needs a build that uses Play Billing in the Play Console, which versionCode 2 is. It's
safe to run again: it sets the same names and prices.

## App Store Connect: the age rating

`app_rating_config.json` answers Apple's current questionnaire (the 2025 one, with 4+, 9+, 13+, 16+ and 18+). Its
keys are the App Store Connect API's, which `deliver` sends as they are (checked with fastlane 2.232.2's own mapping
code: nothing is renamed or dropped). The answers, with the content behind each:

| Question | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | Frequent | Told, never shown, but in four games: villagers "eaten" by the werewolf in every Werewolf story, pirate sea battles and sword fights, space chases in Frootopia, Nuclear War's bombs. Nothing graphic. |
| Realistic violence | Infrequent | Nuclear War names real countries and real cities ("Paris has been vaporized"). No one is described being hurt, but a vaporized real city implies it. The leaders have parody names. |
| Prolonged graphic or sadistic violence | None | |
| Guns or other weapons | Frequent | Bombs are bought every round of Nuclear War; cannons, cutlasses and swords in Pirate Quest; an anti-gravity gun and lasers in Frootopia. |
| Horror or fear themes | Infrequent | The Werewolf (claws, "screams", a bloodied barn, and a villager "eaten" in every story), ghosts in Pirate Quest. Cartoon, and played for laughs, in one game of eight: "Infrequent/Mild" is the fair reading. "Frequent" would also give 13+, so it wouldn't change the rating if Apple thinks otherwise. |
| Profanity or crude humour | Infrequent | Nuclear War's leaders are Yuri Poo-tin, Iona Butt, Roger Shufflebottom and Hoo Flung Dung; a wombat poop fact in Leaning Tower of Pizza. No swearing. (See "Nuclear War: the policy risk" below about two of those names.) |
| Mature or suggestive themes | Infrequent | Apple counts "war or political strife": Nuclear War, sanctions and all. One game of eight. |
| Alcohol, tobacco or drug use or references | Infrequent | The Werewolf's barmaid serves ale, cider and wine (one pack line is "the wine was drugged"; one villager leaves "howling drunk"); Pirate Quest's crew drinks in a tavern. |
| Sexual content or nudity, graphic or not | None | ("Naked eye" in a trivia fact is the only hit.) |
| Medical or treatment information | None | |
| Simulated gambling | Infrequent | Pirate Quest's dice game: wager 10 coins, roll three dice. In-game coins only; they can't be bought or cashed out. |
| Contests | Infrequent | Leaning Tower of Pizza's true-or-false challenge keeps a best streak, on the device only. |
| Gambling (real money), loot boxes | No | |
| Unrestricted web access, user-generated content, messaging and chat, social media | No | No web views, no posting, no chat. |
| Advertising | No | |
| Parental controls, age assurance | No | |
| Health or wellness topics | No | |
| Made for Kids (`kidsAgeBand`) | none | Not in the Kids category. |
| Age rating override | none | |

**Result: 13+.** Five answers each set 13+ by Apple's table: realistic violence, alcohol references and simulated
gambling (Infrequent is already 13+ for those three), and weapons and cartoon or fantasy violence (Frequent is 13+).
Mature themes alone would give 9+. Answering "Frequent" to mature themes would give 16+, and "Frequent" alcohol
references 18+; neither is a fair reading of the app as a whole.

What a lower rating would take: 13+ is effectively fixed by the content. 9+ would need all five gone: the Pirate
Quest dice game, the drink references and Nuclear War's real cities, **and** weapons and cartoon violence honestly
down to "Infrequent". That last part isn't realistic while bombs are bought every round of Nuclear War and a
villager is killed in every Werewolf story. So it isn't a form question, and it isn't three small content changes
either.

## App Store Connect: App Privacy

`app_privacy_details.json` declares the usage data (until the accessibility release it said Data Not Collected), and
`PrivacyInfo.xcprivacy` declares the same collected data types; `fastlane ios check` and `tools/check_store.py`
compare the two.

| Data type (App Store Connect) | What it is here | Purpose | Linked to the player | Used to track |
|---|---|---|---|---|
| Usage Data: Product Interaction | tabs and games opened, how far games get, the intro and welcome finished or skipped | Analytics | Yes | No |
| Identifiers: Device ID | the random install ID | Analytics | Yes | No |
| Purchases: Purchase History | a purchase started and how it ended, restores (product ids, no prices or account) | Analytics | Yes | No |
| Diagnostics: Other Diagnostic Data | a game's error (which node), a pack download's result, time and size | Analytics | Yes | No |

- **Linked:** the install ID is persistent, and "Delete my usage data" finds its rows by it, so Apple counts the
  data as linked to the player, even with no name or account; "not linked" would need it de-identified before it's
  collected. When sign-in links the ID to an account, the account data (an email or user ID) is added here too.
- **Not tracking:** nothing is combined with other companies' data, shared with data brokers or used for
  advertising. So there's no App Tracking Transparency prompt, and `NSPrivacyTracking` is false.
- Speech recognition is Apple's own (`SFSpeechRecognizer`), under Apple's terms; the app doesn't record or keep
  audio, and the usage data never includes it, nor what's said or typed.
- Purchases are StoreKit's; the app reads which products the account owns, and the usage data records the product
  id and the outcome (Purchase History, above).
- Pack downloads name a file and nothing else; Cloudflare's standard logs (IP address, time, file) are kept briefly
  to run the service, not linked to anyone and not used for tracking.
- **The Apple Watch app** changes none of this: it collects nothing (its own `PrivacyInfo.xcprivacy` declares no data
  and no tracking), and what passes between it and the iPhone (the watch link, above) stays on the player's own
  devices, through WatchConnectivity.
- **Privacy Choices URL** (App Privacy, on the website): `https://epicaudiogames.com/privacy#usage-data`, where the
  policy says how to turn the usage data off and delete it.

## App Store Connect: the other questions

- **Content rights:** "Does your app contain, show, or access third-party content?" The games come from Mini Games
  and the voices from ElevenLabs. If Hugo FM owns or has licensed all of it, answer that it has the rights. **The
  user must confirm.**
- **Export compliance:** no non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO` is in the build already;
  the only encryption is the system's HTTPS).
- **Sign-in:** none, so no demo account.
- **Advertising identifier:** not used.
- **Pricing:** free, with the three in-app purchases.
- **Devices:** iPhone (upright) and iPad (any way, any window size), iOS and iPadOS 17 or later, with the Apple Watch
  app inside; Macs and Vision Pro as "Designed for iPad" (Devices, above).
- **Accessibility labels** (Apple's Accessibility Nutrition Labels, on the app's page): declared at the production
  submission, after the checks on real phones at the end of `docs/DESIGN.md`, not for TestFlight. The candidates:
  VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast and
  Reduced Motion, each once it's checked on a phone; "Captions" may fit, since every spoken line is shown as text
  (check Apple's definition first). Then the description can say "Works with VoiceOver" too.
- **Release:** the metadata lane sets the version to release manually, so approval doesn't publish it: click
  "Release This Version" once the website pages are live.

## Google Play Console: the forms

The app exists in the Play Console (**Epic Audio Games**, default language English (United States), **Game**,
**Free**). Fill these in under Policy and programs, App content. Recommended answers:

### Privacy policy

https://epicaudiogames.com/privacy

### App access

**All functionality is available without any special access.** There's no login. Packs are bought, not unlocked by
an account, and the free parts of every game are open.

### Ads

**No, my app does not contain ads.**

### Content rating (IARC questionnaire)

Email: james@hugo.fm. Category: **Game** (all other categories describe non-game apps). Answers:

- **Violence:** Yes, fantasy violence, told in narration and text only, with no images and no gory detail. Human
  characters are killed off-screen by a fantasy creature: in every Werewolf story the werewolf kills a villager, told
  afterwards ("Grave News. The Baker was eaten!", "The Butcher has already been killed by the werewolf", "a cleaver
  washed down my river, still bloody"). Also pirate sea battles and sword fights, and Nuclear War's bombs that
  "vaporize" real cities, with no people described. If the form asks whether humans or human-like characters are
  harmed, answer **yes**: killed off-screen by a fantasy creature, narrated, not shown, no blood or gore described in
  detail. If it asks about realistic settings, say yes for Nuclear War, in narration only. Keep **fantasy** as the
  main kind of violence. Wrong answers here are what get an app re-rated or taken down, so err towards yes.
- **Fear:** Yes, mild: a werewolf mystery and pirate ghosts, played for laughs. Nothing intended to frighten young
  children.
- **Sexuality:** No.
- **Language:** No swearing. Crude humour: Yes, mild (toilet-humour leader names in Nuclear War).
- **Controlled substances:** References to alcohol: Yes (ale, cider and wine at the inn in The Werewolf; a tavern in
  Pirate Quest). Use shown: no images; one or two lines describe a character drunk. No tobacco or drugs, apart from
  one pack line about a drugged drink.
- **Gambling:** Real-money gambling: No. Simulated gambling: Yes (Pirate Quest's dice, for in-game coins that can't
  be bought or cashed out).
- **Discrimination or hate:** the questionnaire asks whether the app has content that could be seen as demeaning
  people on the grounds of race, ethnicity, nationality or religion. The honest answer, while Nuclear War has its
  leader "Hoo Flung Dung" (a mock-Chinese name joke), is **yes, mild**: one parody leader name, spoken, in a game
  where every country's leader has a joke name. If that name is changed (see below), the answer is **no**.
- **Miscellaneous:** Users interact or exchange content: No. Shares location: No. Digital purchases: Yes.
  Unrestricted internet: No (Settings' links open the phone's browser on three fixed pages: privacy, support and
  accessibility). Web browser or search engine: No. Nazi or extremist symbols: No.

Expect roughly a 12+ or Teen rating across regions (PEGI 12, ESRB Teen, USK 12), for the fantasy violence, the
simulated gambling and the alcohol references; a "yes" on discrimination could push some regions higher. The
questionnaire sets the exact rating in each region.

### Target audience and content

- **Target age groups:** 13 to 15, 16 to 17, and 18 and over. Not under 13: the content is rated 13+, and with
  children in the audience Google's Families policy would apply, including to Android speech recognition, which can
  send a child's voice to Google's online service.
- **Could the store listing unintentionally appeal to children?** The covers are cartoon art, so Google may think
  so. Answer honestly when asked. If Google decides it appeals to children, the app meets some of the Families
  rules (no ads), but the usage data (a persistent install ID sent to our server) and the speech question would
  both need answers.
- If the audience should include children after all, change the privacy policy's Children section too.

### Data safety

Changed with the accessibility release (versionCode 3): the app now sends usage data to our server. Update the form
before that build goes to testers; it's what the listing's Data safety section shows.

- **Does your app collect or share any of the required user data types?** **Yes**, it collects; it shares
  nothing (no third party gets any of it).
- **Is all of the user data collected by your app encrypted in transit?** **Yes** (HTTPS to epicaudiogames.com).
- **Do you provide a way for users to request that their data is deleted?** **Yes**: in the app (Settings,
  Privacy, "Delete my usage data") and by email (james@hugo.fm). There are no accounts, so no account-deletion URL.
- **The data types**, each **collected**, **not shared**, not processed ephemerally, purpose **Analytics**, and
  **optional** (players can turn it off in Settings, and the welcome says so with a "Turn off" button):
  - **App activity > App interactions:** tabs and games opened, how far games get.
  - **Device or other IDs:** the random install ID (not the advertising ID, which the app doesn't use).
  - **Financial info > Purchase history:** a purchase started and how it ended, restores.
  - **App info and performance > Diagnostics:** a game's error, a pack download's result and time.
- One judgment call: sharing is on by default with an off switch. If Google reads "optional" as opt-in only,
  answer **required** for the same four types instead; nothing else changes.
- Unchanged: speech goes to the phone's own speech recognition service through Android's `SpeechRecognizer` API,
  and that service (usually Google's) handles it; the app holds no audio and sends none. Play's billing system
  handles payments under its own terms. Pack downloads carry no user data. The IP addresses in Cloudflare's and
  Railway's standard request logs, kept briefly to run the service, aren't used for location or to identify anyone,
  and the usage-data server itself uses one only in memory, for rate limiting.
- Unchanged by the Wear OS app: it collects nothing and sends nothing to us. The phone tells the player's own watch
  the open game's title, its state in words, the big button's name and two yes/no values, and the watch sends back
  "primary" or "pause": the app's state, not data about the player. Google Play services' Data Layer carries it
  between the two (over Bluetooth, or through Google's servers end-to-end encrypted), readable only by the same app
  with the same signature (`docs/WEAR_OS.md`). Google's data-disclosure page for Play services
  (developers.google.com/android/guides/play-data-disclosure) covers only its base libraries, not the Wearable API:
  read the Wearable API's own guidance once more before the production submission.

### Other declarations

- **Advertising ID:** the app doesn't use it.
- **Government app, financial features, health, news, COVID-19:** none or no.
- **Store settings:** category Adventure (above), contact email james@hugo.fm, website https://epicaudiogames.com/.
  The phone field in Store settings is optional, but the EU trader declaration below makes a phone number public in
  the EU anyway, so decide which number that is first and use the same one here.

## Both stores: EU trader status (Digital Services Act)

Both App Store Connect (Business → the developer account's Digital Services Act compliance) and the Play Console
(Account details → Trader status) require a declaration before the app can be offered in the EU. The packs are sold
in the app, so Hugo FM is a **trader**. Both stores then verify, and show on the EU store pages:

- the trader's name: the legal entity on the developer account (Hugo.FM Games Limited, if that's who holds it);
- the address: by default the account's registered address (Companies House has 55 Station Road, Manningtree,
  Essex, CO11 1EB for both Hugo.FM companies);
- a phone number and an email address.

Choose before declaring: +447468595532 is the App Review contact number and would become public in the EU. A
business number (or a landline that forwards) avoids publishing a personal mobile. The email can be james@hugo.fm or
a support address. Without the declaration, Apple and Google stop offering the app in the EU.

Google Play: done (checked 7 October 2026). The app is in the verified organisation account HUGO.FM GAMES LIMITED,
whose public developer profile already shows the address above, +447468595532 and james@hugo.fm. The Play Console
has no separate trader form for it. App Store Connect still needs its declaration, with the same number.

## Google Play: the developer account

The app is in the verified organisation account HUGO.FM GAMES LIMITED, which can publish to production without
first running a closed test. (A personal account made after November 2023 would have needed a closed test with at
least 12 testers opted in for 14 days in a row.) `fastlane android internal track:alpha` uploads to closed testing,
if one is wanted anyway, for example with blind players.

## Nuclear War: the policy risk

Nuclear War is a port of the Alexa skill, and two of its leader names carry review risk on both stores:

- **"Hoo Flung Dung"**, the Chinese leader, is a mock-Chinese ethnic-name joke. Apple's guideline 1.1.1 covers
  content that's discriminatory about national or ethnic origin, and Google has a Hate Speech policy and an IARC
  question on it. This is the one most likely to draw a rejection or a "yes" on discrimination.
- **"Yuri Poo-tin"** parodies a real head of state, and the player bombs real countries' cities. Apple's 1.1.2 says
  the enemy in a game can't solely target a real government. The defence is that all five countries are playable
  and any can be the target, so no one country is singled out; the review notes say exactly that.

The other names (Iona Butt, Roger Shufflebottom) are toilet humour, not about anyone's origin. Renaming means new
recordings of the leaders' calls (`games/nuclear-war/clips.json`) and lines in `lines.json`, so it's your content
decision. The least is renaming "Hoo Flung Dung". The review notes describe the leaders as fictional parody names
and don't draw attention to them.

## Still to do before publishing

- **The privacy policy's usage-data section, live first.** Deploy the website (`docs/RELEASE.md`, Railway) and check
  that https://epicaudiogames.com/privacy, /support and /accessibility say 200, and that the policy lists every event
  the apps send (`tools/check_store.py` compares its `data-event` list with `web/analytics/events.json`), before any
  build with usage data reaches testers, before `fastlane ios metadata`, and before the Play Console's forms. Both
  stores check the pages.
- **The usage data's legal basis.** On by default, with notice and an off switch, rests on legitimate interests.
  For players in the EU, ePrivacy (Article 5(3)) generally wants consent before an app stores an ID on the phone for
  analytics, and the UK's exception for statistics is narrow. Get a legal opinion before production, or ask first
  (instead of on by default) when the phone's region is in the EU or EEA. Apple's 5.1.1(ii) accepts legitimate
  interests only with full GDPR compliance.
- **Both stores' privacy answers:** `fastlane ios privacy` (App Privacy, above) and the Privacy Choices URL, and
  Play's Data safety form (above), with the release.
- **Buy, download and restore a pack** on both stores with test accounts (a sandbox Apple ID in TestFlight, a
  licence tester on Google Play) before submitting. The packs are on R2 (`py -3.13 tools/check_packs.py --sha`
  checks them against the catalog), and the lanes stop if a build would download them from anywhere else.
- **The legal entity.** The privacy policy names Hugo.FM Games Limited (company 14615936) as the controller. Confirm
  that's the company on the Apple and Google developer accounts; if it's Hugo.FM Limited (11911713), change the two
  places in `web/public/privacy.html`.
- **VoiceOver and TalkBack on real phones** (the checks at the end of `docs/DESIGN.md`), before either listing claims
  them, and before Apple's accessibility labels.
- **The watch apps on real watches** (`docs/WATCH.md`, `docs/WEAR_OS.md`), before either listing mentions them; the
  Apple Watch target added in Xcode first, and Wear OS screenshots, which need a Wear OS emulator, before the Wear OS
  app can go on its track.
- **The iPad, Mac and Vision Pro:** the 13" iPad screenshots (the Mac's `StoreScreenshotsUITests` run) before App
  Review; the iPad app tried on an Apple-silicon Mac and the visionOS simulator, or turned off for them in Pricing and
  Availability.
- **Chromebooks without a touchscreen:** whether to declare the touchscreen optional (Devices, above).
- **Nuclear War's leader names**: your call (above).
- **EU trader status** in App Store Connect, with +447468595532 (Google Play is done; it is an organisation account).
- **Store art:** the new icon, feature graphic, screenshots and preview video, once approved (`docs/STORE_ART.md`).
  The icon (icon-03) is the owner's pick; the feature graphic (feature-02), the screenshots' captions and the Play
  preview's cut wait for gates 4 and 5. The Play screenshots of the Shop show "Installed" (the emulator had the
  packs), not a price.
