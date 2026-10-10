# fastlane: the App Store

Everything the App Store shows about Epic Audio Games lives here as files, and fastlane sends it to App Store
Connect (app id 6820105215, bundle id `com.epicaudiogames.app`, version 1.0). Nothing here ever submits the app for
review: that stays a button in App Store Connect.

| Here | What it is |
|---|---|
| `metadata/` | the listing, in deliver's layout: `en-US/` (name, subtitle, description, keywords, promotional text, support, privacy and marketing URLs), `copyright.txt`, the categories (`primary_category.txt` and the others), and `review_information/` (App Review's contact and notes) |
| `app_rating_config.json` | the age rating answers, as App Store Connect's API names them (`violenceCartoonOrFantasy`, `lootBox`, ...) |
| `screenshots/en-US/` | the App Store screenshots, up to 10 per size: 6.9-inch (1320 x 2868) and 6.3-inch (1206 x 2622) iPhone, both made from the same captures (`tools/make_art.py shots ios`); 6.5-inch (1284 x 2778) works too |
| `app_previews/en-US/` | optional: the App Previews, up to 3 per size, 886 x 1920, 15 to 30 seconds (`tools/make_preview.py`). deliver reads the iPhone size from the file's name: `01_IPHONE_67.mp4` is the 6.9-inch group |
| `iap_review/<product id>.png` | each in-app purchase's screenshot for App Review (at least 640 x 920): `frootopia_stories`, `alien_customs_levels`, `the_werewolf_stories` |
| `app_privacy_details.json` | the App Privacy answers (fastlane's `upload_app_privacy_details_to_app_store` format): the usage data, as `docs/STORE_LISTING.md` explains |
| `testflight/what_to_test.txt` | each TestFlight build's "What to Test" (4,000 bytes; fastlane takes out any `<`) |
| `metadata/review_information/attachment.*` | optional: one file for App Review (`.mov`, `.mp4`, `.pdf`, `.png` or `.jpg`), such as a short video of a game played by voice |
| `Fastfile`, `Appfile` | the lanes below |

## Once, on each Mac

fastlane 2.232.2 or later from Homebrew (`brew install fastlane`; the previews lane needs 2.233.0 or later, so
`brew upgrade fastlane`), Xcode 26 (App Store Connect takes only its builds), and ffmpeg (`brew install ffmpeg`:
`check` reads the App Previews with ffprobe). The App Store Connect API key comes from three environment variables.
Neither the Fastfile nor this README holds a key, its id or its path:

```
export ASC_KEY_ID=<the key's id>
export ASC_ISSUER_ID=<the team's issuer id>
export ASC_KEY_PATH=<path to AuthKey_<key id>.p8, outside any repo>
```

The key has to be a **team key** (Users and Access → Integrations → App Store Connect API → Team Keys) from the
team that owns app 6820105215, with the App Manager or Admin role. A key from another team, or an individual key,
can't see this app. Put the three lines in your shell profile, or in `ios/fastlane/.env`, which fastlane reads by
itself and git ignores. Keep the `.p8` file itself out of this repo (git ignores `*.p8` anyway); `check` warns if
`ASC_KEY_PATH` points inside it.

## The lanes

Run them from `ios/`:

```
fastlane ios check                    # checks every file below, offline; run it first
fastlane ios metadata                 # the listing, categories, review contact, age rating and price (free)
fastlane ios screenshots              # the App Store screenshots, replacing the ones there
fastlane ios previews                 # the App Previews, replacing the ones there
fastlane ios iap_review_screenshots   # each in-app purchase's review screenshot (only:<product id> for one)
fastlane ios privacy                  # the App Privacy answers (Apple ID login, see below)
fastlane ios beta                     # a build on TestFlight (dry_run:true shows what it would do)
```

From the repo root, `python3 tools/check_store.py` (`py -3.13` on the Windows PC) checks the same files without Ruby
or fastlane, and Google Play's too.

- **check** sends nothing. It checks the listing's required files and Apple's length limits (the review notes
  too), the https URLs, the categories against App Store Connect's ids, the age rating answers (the same mapping
  deliver applies, and the values Apple takes), the privacy answers, the screenshot sizes (deliver's own check: one
  of 6.9, 6.5 or 6.3 inches, and a warning without both 6.9 and 6.3) and that none has an alpha channel, and the
  review screenshots. It checks the app icon (1024 x 1024 with no alpha channel, which App Store Connect refuses:
  ITMS-90717; a warning without iOS 18's dark and tinted icons), the App Previews against Apple's specs (with
  ffprobe), What to Test, and that the builds' pack server is R2. It also checks the app's privacy manifest
  (`EpicAudioGames/Resources/PrivacyInfo.xcprivacy`) against the required-reason APIs the Release code calls
  (`mach_absolute_time`, `UserDefaults`, free disk space and the others): App Store Connect refuses a build that uses
  one undeclared (ITMS-91053). And it checks that the manifest's collected data types say what
  `app_privacy_details.json` says (the same data, purposes, link to the player, no tracking). The upload lanes run
  their part of it first and stop before contacting Apple if anything is wrong.
- The age rating's `socialMedia` question is in App Store Connect's API (`AgeRatingDeclaration`, a boolean) but not
  yet in fastlane 2.232.2's list. deliver sends it as it is, and `check` knows it (`ASC_ONLY_RATING_BOOLEANS`), so
  keep it: without it that question would be left unanswered.
- **metadata** edits only the version that App Store Connect is preparing, and only when its number is
  `MARKETING_VERSION` in `ios/Config/Base.xcconfig`. It never creates or renames a version, and it stops if the
  version is waiting for review. It sets the same values every time, so it's safe to run again, with one catch:
  App Review's attachment. With `metadata/review_information/attachment.*` there, it uploads that file; without it,
  deliver **removes any attachment added on the website**. So keep a demo video in that folder rather than only on
  the website. The lane sets the release to **manual**: once App Review approves 1.0, it goes live only when you
  click "Release This Version" (after the website's /privacy and /support pages are live). The price is set
  through App Store Connect's price schedule API: deliver's own `price_tier` still uses Apple's old price tiers,
  which App Store Connect has stopped accepting. If the app isn't on sale in any country yet, the lane says so (see
  below).
- **iap_review_screenshots** finds each product by its id, then reserves the upload, sends the parts where Apple
  says, and commits it with its checksum (App Store Connect API `inAppPurchaseAppStoreReviewScreenshots`). A
  screenshot already there with the same checksum is left alone.
- **previews** uploads `app_previews/<language>/` with deliver's `app_previews_path` (fastlane 2.233.0 and later;
  with an older fastlane the lane says so and stops), replacing the previews there, with the poster frame 5 seconds
  in. Nothing else on the version changes. Without a new enough fastlane, add the videos on the version's page in App
  Store Connect instead.
- **privacy**: Apple doesn't let API keys change App Privacy answers, so this lane logs in as you. Set
  `FASTLANE_USER` to your Apple ID (or pass `apple_id:you@example.com`); it asks for the password and a 2FA code.
  `publish:false` uploads the answers without publishing them. It stops if the answers and the privacy manifest
  disagree. The Privacy Choices URL (`https://epicaudiogames.com/privacy#usage-data`) is set on the website.
- **beta** builds the Release configuration for devices and uploads it to TestFlight (internal testers only), with
  `testflight/what_to_test.txt` as its What to Test: fastlane then waits only until the build appears in App Store
  Connect, sets that, and returns without waiting for Apple to process it. The build number is the time,
  `yyyymmddHHMM`, passed to xcodebuild, so no file changes. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
  `Base.xcconfig` stay as they are. It needs the real `content/` (a Release build fails without the audio; README,
  "Building the content") and the R2 pack server (`EPIC_PACKS_URL` in `Base.xcconfig`). The lane stops if the build
  would hide buying packs (App Review couldn't find the in-app purchases) or download them from anywhere but R2 (a
  `Local.xcconfig` that sets `EPIC_PACKS_URL` wins over `Base.xcconfig`). `allow_no_packs:true` builds without a
  pack server and `allow_other_packs:true` with another one, for a TestFlight build that isn't going to App Review;
  `dry_run:true` shows the address it would use. Signing is automatic, with this Mac's Xcode account and
  `DEVELOPMENT_TEAM` from `Local.xcconfig`; `cloud_signing:true` signs with the API key instead (that needs an Admin
  key). The `.ipa` and its logs go to `ios/build/testflight/`.

## Only on the App Store Connect website

Once, before the first submission:

- **Agreements, Tax and Banking**: the Paid Apps agreement, for the in-app purchases.
- **Pricing and Availability**: the countries (the metadata lane sets the price to free, and warns until a country is
  chosen).
- **App Information → Content Rights**: whether the app shows third-party content.
- **App Privacy → Privacy Choices URL**: `https://epicaudiogames.com/privacy#usage-data`, where the policy says how to
  turn the usage data off and delete it.
- **Accessibility** (the App Store's accessibility labels): at the production submission, once the checks on real
  phones in `docs/DESIGN.md` have passed; nothing is claimed before then.
- **The version page**: pick the TestFlight build. Under "In-App Purchases and Subscriptions", add the three packs,
  since a first in-app purchase goes to review with a version. Then **Add for Review**.

Encryption is already answered in the app (`ITSAppUsesNonExemptEncryption = NO` in `Config/App.xcconfig`), so
TestFlight doesn't ask.

## The first time, in order

```
fastlane ios check
fastlane ios metadata
fastlane ios screenshots
fastlane ios previews
fastlane ios iap_review_screenshots
fastlane ios privacy
fastlane ios beta
```

Then do the website steps above. `docs/RELEASE.md` has the whole release, both apps, in order.
