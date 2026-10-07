# Store listings

The words for both stores live in the repo as plain text files, laid out for fastlane: `fastlane deliver` reads
`ios/fastlane/`, `fastlane supply` reads `android/fastlane/`. Those files are the source of truth. This page says
where each field lives, and gives the answers for the forms only the App Store Connect and Play Console websites can
fill in. Nothing here has been uploaded yet.

The public pages the listings link to are on the website: `web/public/privacy.html` (epicaudiogames.com/privacy)
and `web/public/support.html` (epicaudiogames.com/support).

## The facts the copy rests on

Checked against the code on 7 October 2026. If one of these changes, the listings, the privacy policy and the
answers below change with it.

- **Answering:** speak, type, or tap one of the question's options, shown as chips at the end of the chat. Every
  word is shown as it's spoken. The mic opens by itself after each question.
- **Speech:** iOS uses `SFSpeechRecognizer`, on the device where the iPhone supports it and otherwise on Apple's
  servers (`SpeechListener.swift`). Android uses the phone's `SpeechRecognizer`, which is usually Google's: offline
  where the phone has English, else online (`Listener.kt`). The app never records audio or sends it to us.
- **Network:** the only requests the apps make are pack downloads from our pack server (`Store.kt`,
  `PackDownloader.swift`) and the stores' own purchase calls (Play Billing, StoreKit 2). No web views. Each game's
  menu (three dots) has **Help** and **Privacy policy**, which open epicaudiogames.com/support and /privacy in the
  phone's browser: both stores want the privacy policy reachable inside the app.
- **No SDKs** beyond AndroidX, Media3, Compose and Play Billing on Android, and Apple's frameworks on iOS: no ads,
  analytics, crash reporting or tracking. `PrivacyInfo.xcprivacy` declares no tracking and no collected data, and the
  two required-reason APIs the Release code calls: free disk space (E174.1, before a pack downloads) and
  `mach_absolute_time` (System Boot Time, 35F9.1: the mic level meter and the audio graph's timing). `fastlane ios
  check` fails if the code starts using another one undeclared.
- **Saves** are on the device (SharedPreferences on Android, Application Support on iOS). They hold the game's
  place and variables, not what the player said. They can go into the device's own backups (Android
  `allowBackup="true"`; iOS Application Support is backed up). Packs are excluded from iOS backups.
- **Offline:** every game ships inside the app. Buying and downloading packs needs a connection, and so does speech
  on devices that can't recognise English on the device.

## App Store: where each field lives

All under `ios/fastlane/`. `metadata/` is the `deliver` metadata folder; `en-US` is the primary language.

| Field | File | Limit | Now |
|---|---|---|---|
| Name | `metadata/en-US/name.txt` | 30 | 16 |
| Subtitle | `metadata/en-US/subtitle.txt` | 30 | 29 |
| Keywords | `metadata/en-US/keywords.txt` | 100 bytes | 98 |
| Promotional text | `metadata/en-US/promotional_text.txt` | 170 | 153 |
| Description | `metadata/en-US/description.txt` | 4000 | 2481 |
| What's New | none: version 1.0 has no release notes. Add `release_notes.txt` from 1.1 | 4000 | |
| Marketing URL | `metadata/en-US/marketing_url.txt` | | https://epicaudiogames.com/ |
| Support URL | `metadata/en-US/support_url.txt` | | https://epicaudiogames.com/support |
| Privacy policy URL | `metadata/en-US/privacy_url.txt` | | https://epicaudiogames.com/privacy |
| Copyright | `metadata/copyright.txt` | | 2026 Hugo FM (your choice; the legal name would be "2026 Hugo.FM Games Limited") |
| Categories | `metadata/primary_category.txt` and the `*_sub_category.txt`, `secondary_category.txt` files | | see below |
| App Review contact | `metadata/review_information/{first_name,last_name,phone_number,email_address}.txt` | | James Holland, james@hugo.fm, +447468595532 |
| App Review notes | `metadata/review_information/notes.txt` | 4000 | 3270 |
| App Review attachment | `metadata/review_information/attachment.*` (optional; see `ios/fastlane/README.md`) | | none yet |
| Age rating | `app_rating_config.json` (`deliver`'s `app_rating_config_path`) | | 13+ |
| App Privacy | `app_privacy_details.json` (`upload_app_privacy_details_to_app_store`) | | Data Not Collected |

The keywords leave out every word of the name and subtitle, since Apple indexes those already: interactive,
adventure, drama, mystery, werewolf, pirate, speak, talk, offline, trivia, alien, quiz, detective. "radio" and
"headphones" were dropped: Apple rejects keywords that don't describe the app (2.3.7), and "radio" mostly matches
people looking for radio stations. "Audio drama" still matches, since Apple combines keywords with the name.

## Google Play: where each field lives

All under `android/fastlane/metadata/android/en-US/`, the `supply` layout.

| Field | File | Limit | Now |
|---|---|---|---|
| App name | `title.txt` | 30 | 16 |
| Short description | `short_description.txt` | 80 | 80 |
| Full description | `full_description.txt` | 4000 | 2467 |
| Release notes for versionCode 1 | `changelogs/1.txt` (one file per versionCode) | 500 | 169 |
| Release notes for any other versionCode | `changelogs/default.txt` | 500 | 169 |

supply sends these files exactly as they are, without trimming, so a trailing newline counts towards the limit:
`short_description.txt` is exactly 80 characters and must stay without one (`fastlane android check` measures
what supply sends).

The two descriptions differ only where the platforms do. Speech is described as each platform does it, and Family
Sharing is mentioned only on the App Store. Neither description claims VoiceOver or TalkBack for 1.0: VoiceOver works
in the simulator and in the UI tests' accessibility audit, but `docs/IOS.md` still lists it for a real iPhone. Once
that's done, add "Works with VoiceOver. Magic Tap skips the voice, starts listening, or carries on." back to the App
Store description.

## Categories

- **App Store:** primary **Games**, with the subcategories **Adventure** and **Puzzle**; secondary
  **Entertainment**. Five of the eight games are story adventures you steer (Frootopia, Noodle Rush, Signal Decoders,
  Pirate Quest, Alien Customs), and The Werewolf, Signal Decoders and Leaning Tower of Pizza are puzzles: who is the
  werewolf, decoding a signal, true or false. Entertainment is where people browse for radio plays and audio drama,
  which is what the games sound like. Not Kids, and not the Family subcategory, which would clash with a 13+ rating.
- **Google Play:** app type **Game**, category **Adventure**, for the same reason. Play allows one category. Add up
  to five tags in the console (Store settings), from its list: for example Interactive story, Mystery, Single
  player, Offline and Casual.

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
`iaps` lane creates them once the app exists in the Play Console and has a build that uses Play Billing.

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

`app_privacy_details.json` says **Data Not Collected**, which matches `PrivacyInfo.xcprivacy`:

- Apple counts data as collected when it leaves the device in a form the developer (or its partners) can keep. The
  app sends nothing of the player's to us. The required-reason APIs in `PrivacyInfo.xcprivacy` (disk space, system
  boot time) are used on the device only, so the answer stays Data Not Collected.
- Speech recognition is Apple's own (`SFSpeechRecognizer`), under Apple's terms; the app doesn't record or keep audio.
- Purchases are StoreKit's; the app only reads which products the account owns.
- Pack downloads name a file and nothing else. The server's standard access logs (IP address, time, file) are kept
  briefly to run the service, not linked to anyone and not used for tracking. If the pack server ever logs more,
  or keeps logs long, look at this again.

## App Store Connect: the other questions

- **Content rights:** "Does your app contain, show, or access third-party content?" The games come from Mini Games
  and the voices from ElevenLabs. If Hugo FM owns or has licensed all of it, answer that it has the rights. **The
  user must confirm.**
- **Export compliance:** no non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO` is in the build already;
  the only encryption is the system's HTTPS).
- **Sign-in:** none, so no demo account.
- **Advertising identifier:** not used.
- **Pricing:** free, with the three in-app purchases.
- **Devices:** iPhone only, portrait, iOS 17 or later.
- **Accessibility labels** (optional, on the app's page): leave VoiceOver unclaimed until it's been tried on a real
  iPhone (`docs/IOS.md`); it holds in the simulator and in Apple's accessibility audit in the UI tests. Then claim it
  here and put the line back in the description. "Captions" may fit, since every spoken line is shown as text;
  check Apple's definition first. Leave the rest unclaimed until they're checked.
- **Release:** the metadata lane sets the version to release manually, so approval doesn't publish it: click
  "Release This Version" once the website pages are live.

## Google Play Console: the forms

The app doesn't exist in the Play Console yet. Create it as **Epic Audio Games**, default language English (United
States), **Game**, **Free**, then fill these in under App content. Recommended answers:

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
  Unrestricted internet: No (the Help and Privacy policy links open the phone's browser on two fixed pages). Web
  browser or search engine: No. Nazi or extremist symbols: No.

Expect roughly a 12+ or Teen rating across regions (PEGI 12, ESRB Teen, USK 12), for the fantasy violence, the
simulated gambling and the alcohol references; a "yes" on discrimination could push some regions higher. The
questionnaire sets the exact rating in each region.

### Target audience and content

- **Target age groups:** 13 to 15, 16 to 17, and 18 and over. Not under 13: the content is rated 13+, and with
  children in the audience Google's Families policy would apply, including to Android speech recognition, which can
  send a child's voice to Google's online service.
- **Could the store listing unintentionally appeal to children?** The covers are cartoon art, so Google may think
  so. Answer honestly when asked. If Google decides it appeals to children, the app already meets most of the
  Families rules (no ads, no data collected), but the speech question would need an answer.
- If the audience should include children after all, change the privacy policy's Children section too.

### Data safety

- **Does your app collect or share any of the required user data types?** **No.**
- Why: Google counts data as collected when the app sends it off the device. The app sends nothing of the
  player's. Speech goes to the phone's own speech recognition service through Android's `SpeechRecognizer` API,
  and that service (usually Google's) handles it. The app holds no audio and sends none. Play's billing system
  handles payments under its own terms, and Google says data a payment service collects itself needn't be declared.
  Pack downloads carry no user data; the IP address in the server's access logs isn't used for location or to
  identify anyone.
- Two judgment calls, if a reviewer disagrees: the app reads the account's purchases from Play Billing (they stay
  with Google; nothing goes to our servers), and the pack server's access logs hold IP addresses for a short time.
  The cautious alternative is to declare **Financial info > Purchase history**: collected, not shared, required, for
  App functionality. That would also need the policy to say so.
- The later questions (encryption in transit, deletion requests) only appear once something is declared. Pack
  downloads should be HTTPS in any case. There are no accounts, so no account-deletion URL is needed.

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

Which kind of account the app goes in changes the timeline:

- **Organisation** (recommended, as Hugo.FM Games Limited): needs the company's D-U-N-S number (free from Dun &
  Bradstreet, which can take a few days to a couple of weeks), and can publish to production straight away.
- **Personal**, made after November 2023: before production, a closed test with at least 12 testers opted in for
  14 days in a row, then an application for production access. Plan that in (`fastlane android internal
  track:alpha` uploads to closed testing).

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

- **The pack server**, live on HTTPS, and its address in the builds (`EPIC_PACKS_URL` in `ios/Config/Local.xcconfig`,
  `epicPacksUrl` for Gradle). Without it the builds hide buying packs, so App Review can't find the in-app purchases;
  `fastlane ios beta`, `fastlane android build` and `fastlane android internal` now stop unless it's set. Then buy
  and download a pack in TestFlight with a sandbox account before submitting. The privacy policy's "Downloading
  packs" section describes that server's standard logs, wherever it's hosted.
- **Deploy the website** (`railway up` from `web/`), then check `curl -sI https://epicaudiogames.com/privacy` and
  `curl -sI https://epicaudiogames.com/support` both say 200, before `fastlane ios metadata` or entering the URL in
  the Play Console. Both stores check them.
- **The legal entity.** The privacy policy names Hugo.FM Games Limited (company 14615936) as the controller. Confirm
  that's the company on the Apple and Google developer accounts; if it's Hugo.FM Limited (11911713), change the two
  places in `web/public/privacy.html`.
- **VoiceOver on a real iPhone** (`docs/IOS.md`), before claiming it in the description again.
- **Nuclear War's leader names**: your call (above).
- **EU trader status** in App Store Connect, with +447468595532 (Google Play is done; it is an organisation account).
- Optional: screenshots with the real `content/` covers (the website's covers are used now; five are 338 x 190,
  scaled up, so slightly soft).
