# fastlane: Google Play

Everything Google Play shows about Epic Audio Games lives here as files, and fastlane sends it to the Play Console
(package `com.epicaudiogames.app`). The app is in the HUGO.FM GAMES LIMITED organisation account, and steps 1 to 5
below were done on 7 October 2026. Version 2 (1.0) is on the internal testing track, for the "Epic Audio Games"
tester list. Steps 6 and 7 (App content, EU trader status) are still to finish.

## A new build

1. Raise `versionCode` in `android/app/build.gradle.kts`. Google never takes the same version code twice, including
   one that was uploaded but never released.
2. Optional: add `metadata/android/en-US/changelogs/<versionCode>.txt` for the release notes. Without it the lane
   sends `changelogs/default.txt`.
3. From `android/`, run `fastlane android internal`. It builds, signs and uploads to internal testing, where the
   testers get it within minutes and Google doesn't review it.

The keys' paths come from `android/fastlane/.env` (git ignores it). The upload key's password comes from the
Keychain (see Keys below).

Google Play also has minimum versions: target SDK 36 and Play Billing Library 8 or newer (both as of October 2026).
The app uses `billing-ktx` 8.0.0 because 8.1 and later need Kotlin 2.2, and this project is on Kotlin 2.0.21.

| Here | What it is |
|---|---|
| `metadata/android/en-US/` | the listing, in supply's layout: `title.txt` (30 characters), `short_description.txt` (80), `full_description.txt` (4,000), `images/icon.png` (512 x 512, 32-bit with alpha), `images/featureGraphic.png` (1024 x 500, no alpha), `images/phoneScreenshots/` (2 to 8, 9:16, no alpha), and `changelogs/<versionCode>.txt` or `changelogs/default.txt` (a build's "what's new", 500) |
| `games/catalog.json` (repo root) | the packs' product ids |
| `PLAY_PRODUCTS` in the `Fastfile` | each pack's Play name and description (the names are the App Store ones) |
| `Fastfile`, `Appfile` | the lanes below |

## Keys

The Fastfile never holds a key or a key's path: they come from environment variables. Keep the files outside this
repo, for example in `~/keys/` (git ignores `*.jks`, `*.keystore` and `android/fastlane/*.json` anyway):

```
export PLAY_JSON_KEY="$HOME/keys/epicaudiogames-play.json"          # the service account's key (step 4 below)
export EAG_UPLOAD_KEYSTORE="$HOME/keys/epicaudiogames-upload.jks"   # the upload key (step 3 below)
export EAG_UPLOAD_KEY_ALIAS=upload
export EAG_UPLOAD_KEYSTORE_PASSWORD="$(security find-generic-password -a "$USER" -s eag-upload-keystore -w)"
export EAG_UPLOAD_KEY_PASSWORD="$EAG_UPLOAD_KEYSTORE_PASSWORD"
```

The passwords stay in the macOS keychain: `security add-generic-password -a "$USER" -s eag-upload-keystore -w`
stores one (it asks for it). fastlane also reads `android/fastlane/.env` by itself, which git ignores. `check` warns
if `PLAY_JSON_KEY` or `EAG_UPLOAD_KEYSTORE` points inside this repo.

The pack server's address goes in `~/.gradle/gradle.properties` (`epicPacksUrl=https://...`) or
`ORG_GRADLE_PROJECT_epicPacksUrl`. Without it a release build hides buying packs, so `build` and `internal` stop
unless you pass `allow_no_packs:true`.

## Once, in the Play Console and Google Cloud

1. **Create the app.** In the Play Console, choose Create app: the name is Epic Audio Games, the default language
   is English (United States), it's a game, and it's free. Accept the declarations. The package name comes with the
   first upload (step 5).
2. **A payments profile** (Setup → Payments profile), so that the packs can be sold.
3. **The upload key.** Google keeps the key that signs the app for users (Play App Signing, which it offers on the
   first upload: take its own key). You sign uploads with an upload key, made once:
   ```
   keytool -genkeypair -v -keystore ~/keys/epicaudiogames-upload.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Hugo FM, O=Hugo FM"
   ```
   Keep a copy of it and its password somewhere safe. If it's ever lost, Google can reset it, since it holds the
   app's real key. `android/app/build.gradle.kts` still signs release builds with the debug key. The lanes don't
   change that file: they hand the upload key to Gradle with Android Gradle Plugin's injected signing properties,
   the same way Android Studio's "Generate Signed Bundle" does. Before uploading, they check that the bundle isn't
   debug-signed.
4. **The service account** that fastlane uses:
   - In Google Cloud (console.cloud.google.com), pick or make a project and enable the **Google Play Android
     Developer API**.
   - Under IAM & Admin → Service accounts, create one (no roles needed). Then use Keys → Add key → JSON, and save the
     key as `$PLAY_JSON_KEY`.
   - In the Play Console, go to Users and permissions → Invite new users, and give the service account's email
     address these permissions on Epic Audio Games: View app information, Release apps to testing tracks, Manage
     testing tracks, and Manage store presence (the listing and the in-app products).
   - Check it with `fastlane run validate_play_store_json_key json_key:$PLAY_JSON_KEY`, which only reads.
5. **The first build, by hand.** Google takes an app's first build only in the Play Console:
   ```
   cd android && fastlane android build    # android/app/build/outputs/bundle/release/app-release.aab
   ```
   Then go to Testing → Internal testing → Create new release, accept Play App Signing, upload the bundle, add
   testers (an email list), and roll it out.
6. **App content** (Policy and programs → App content), only on the website: the privacy policy URL, app access,
   ads, the content rating (IARC) questionnaire, target audience, data safety and the other declarations. The
   answers to give are in `docs/STORE_LISTING.md` ("Google Play Console: the forms"), the one place they're kept.
7. **Store settings** (the category and tags, and the contact details) and the **EU trader status** (Digital
   Services Act): also in `docs/STORE_LISTING.md`. The packs make Hugo FM a trader, and Google then shows the
   verified address, phone number and email on the listing in the EU.

A personal developer account made after November 2023 must run a closed test with at least 12 testers for 14 days
before Google opens production (`fastlane android internal track:alpha` uploads to closed testing). An organisation
account doesn't have to, but needs a D-U-N-S number for the company.

## The lanes

Run them from `android/`, after steps 1 to 5:

```
fastlane android check       # checks the listing, the packs and the release setup, offline; run it first
fastlane android metadata    # the listing's texts and images (validate_only:true has Google check it, changing nothing)
fastlane android iaps        # the three packs as one-time products, $1.99 (dry_run:true prints them, sends nothing)
fastlane android internal    # a signed build on the internal testing track (track:alpha for closed testing)
fastlane android build       # a signed build, not uploaded
```

- **check** sends nothing. It checks the texts against Google's limits as supply sends them (supply doesn't trim, so
  a trailing newline counts: keep `short_description.txt` without one), the images' sizes and colour types (the
  icon with alpha, the rest without), and the packs' names and descriptions (55 and 200 characters). It warns when
  a phone screenshot isn't 9:16 of at least 1080 x 1920, since Google only promotes games whose screenshots are. It
  also warns about anything a release build is missing: the keys, the audio (`content/`), the pack server
  (`epicPacksUrl`), and a versionName that differs from the iPhone app's.
- **metadata** uploads the listing without a build or release notes. Google files a listing against a release, so it
  uses the newest build on the internal track (`track:` and `version_code:` choose another). Images Google already
  has (the same SHA-256) aren't sent again, so it's safe to run again.
- **iaps** creates or updates `frootopia_stories`, `alien_customs_levels` and `the_werewolf_stories`. Their English
  names and descriptions are `PLAY_PRODUCTS` in the Fastfile: the same names as in App Store Connect ("Frootopia:
  Stories 2 to 5", "Alien Customs: 10 More Levels", "The Werewolf: 45 Mysteries"), and the packs' own descriptions.
  `check` stops if a pack in `games/catalog.json` has no entry there. The price is $1.99 in the US, and every other country gets Google's
  conversion of it (`convertRegionPrices`, with local price patterns). The lane then puts each product on sale. It
  uses the one-time products API that Google introduced in 2025 (`monetization.onetimeproducts`, in the
  `google-apis-androidpublisher_v3` 0.96.0 that fastlane 2.232.2 bundles). Each product has one purchase option,
  `buy`, marked legacy-compatible so that the app's Play Billing Library 7 sees an ordinary in-app product. A
  product made in the Play Console keeps its own purchase option. With an older client library the lane falls back
  to the old `inappproducts` API. Run it after the first build is uploaded: Google wants a build that uses Play
  Billing before it takes products.
- **internal** checks that `versionCode` in `android/app/build.gradle.kts` is higher than every build Google has on
  any track (custom closed tracks too), so raise it there before each upload. Then it builds the signed bundle and
  uploads it to the internal testing track, or the one `track:` names (`alpha` is closed testing), with its R8
  mapping file. It also sends `changelogs/<versionCode>.txt`, or `changelogs/default.txt` when there's none. While Google still
  calls the app a draft, it only takes draft releases: if it says so, run `fastlane android internal status:draft`
  and roll the release out in the Play Console.
- **build** makes the same signed bundle without uploading it. `content_dir:<path>` builds with another content
  folder (as `-PepicContentDir`).
