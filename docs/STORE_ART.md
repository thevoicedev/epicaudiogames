# Store art

The app icon (both apps), Google Play's icon and feature graphic, the website's icons and social image, and the framed
store screenshots all come from one tool, `tools/make_art.py` (its code is in `tools/art/`), and the brand settings in
`brand/`. An image model (OpenAI's) draws concept art and nothing else. Every file the apps, stores and website get is
cut from that art here, the same way every time, and every word on the art is set by the tool in Atkinson Hyperlegible
Next, the apps' font. No model ever draws a letter.

The owner approves the art before it ships (`docs/RELEASE.md`): **gate 3**, the icon, and **gate 4**, the screenshot
captions and the feature graphic. Where it stands (10 October 2026):

- **The icon:** the owner picked **icon-03** (gold sound bars in a white speech bubble) at gate 3, and it's exported
  into both apps, the Wear OS app (a copy of the phone's), Play's icon and the website. The Apple Watch app uses the
  iPhone app's 1024 image.
- **The feature graphic:** **feature-02** (golden rings of sound) is picked and exported as the proposal for gate 4,
  with the website's social image cut from the same art. The owner can still swap it (below).
- **The screenshots:** Play's phone, 7-inch and 10-inch sets are captured and framed under the draft captions in
  `brand/shots.json`, for gate 4. The App Store's (iPhone and iPad) are taken on the Mac; there are no Wear OS or
  Apple Watch ones yet (`docs/RELEASE.md`).

## The pipeline

```
models, probe                 what the key's image models can do                                   (a few cents, once)
concepts icon --n 8           one concept per motif in brand/prompts/icon.json                     (paid, ~$0.015 each)
sheet icon                    build/art/review/icon.html + icon.png: every concept, judged         (offline)
                                  ── gate 3: the owner chooses ──
refine icon ID --note ...     new takes on a concept the owner likes but wants changed             (paid, ~$0.02 each)
pick icon ID                  brand/picks.json, brand/masters/ (cuts the emblem out if needed)     (offline)
export all                    every icon into both apps, Play and the website                      (offline)
check                         every exported file against the platforms' and stores' rules         (offline)

concepts feature --n 4        background art for the feature graphic and the social image          (paid)
sheet feature                 build/art/review/feature.html + feature.png, with Play's guides      (offline)
                                  ── gate 4: the owner chooses (or keeps the plain brand background) ──
pick feature ID, export store, export web

store_shots.py / the Mac's StoreScreenshotsUITests     raw captures in build/store-shots/<platform>/raw/
shots android, shots ios      each capture framed under its caption (brand/shots.json)             (offline)
sheet shots                   build/art/review/shots.html + shots.png
                                  ── gate 4: the owner approves the captions ──
```

The preview video is the same idea in motion: `tools/make_preview.py` records takes from the storyboard
(`brand/previews/storyboard.json`) and cuts them into each store's video with captions (`brand/previews/play.json`,
`appstore.json`), for gate 5 (`docs/RELEASE.md`).

Everything after the concepts works offline and costs nothing. `build/art/` is scratch (git ignores it); the concept
art, its costs and the picks are committed, so nothing is ever paid for twice and the Mac makes the same files.

## Setting up

- **Windows:** `py -3.13` has everything (Pillow 10.4.0, numpy, requests, fontTools).
- **Mac:** `python3 -m venv .venv-art && .venv-art/bin/pip install -r tools/requirements-art.txt`, then run the
  commands with `.venv-art/bin/python`. The versions are pinned so the exports match this PC's pixel for pixel.
- **The key** (only for `models`, `probe`, `concepts`, `refine` and a paid `layers`): `OPENAI_API_KEY` from the
  environment, else `OPENAI_API_KEY` or `OPEN_AI` in `../all-minigames-sites/alexa/.env` (the way
  `voice_audition.api_key()` finds ElevenLabs'). The tool never prints, logs or stores it; an error shows the HTTP
  status and OpenAI's message, with anything key-like masked. OpenAI's GPT image models need a verified organisation:
  a 401 or 403 says "key invalid or organisation not verified". Rotate the key once the art is done.
- **Fonts:** `android/app/src/main/res/font/atkinson_hyperlegible_next_{regular,bold,extrabold}.ttf`. Without them
  the feature graphic, the social image and the screenshots can't be made (`check` warns).

## Commands

Run from the repo root (`py -3.13 tools/make_art.py …` here, `python3 tools/make_art.py …` on the Mac).

| Command | What it does |
|---|---|
| `models` | The image models the key can use, what the probe found for each, and which one each job would use. |
| `probe [--model M] [--force]` | Per preferred model, one low-quality 1024 image with a transparent background and one at a custom size (1536x752), recorded in `tools/cache/art/probe.json`. A request a model refused (400) isn't sent again unless `--force`. |
| `concepts icon\|feature [--n 8] [--quality medium] [--motifs 1,3] [--model M] [--budget 5] [--workers 2] [--dry-run] [--force]` | `n` concepts, one per motif in turn (a second round of the motifs makes second takes). Each gets the next id (`icon-01`, `feature-01`, …). `--dry-run` shows the requests and their likely cost; `--force` makes new takes where a concept is cached. |
| `refine icon\|feature ID [--n 4] [--note "…"]` | New takes on one concept: an edit of its image, bolder and simpler, plus the note. They get new ids, with `parent` set. |
| `layers icon ID [--method auto\|local\|edit\|keyed]` | The emblem on a transparent background, which every icon is cut from. `auto` cuts it out here for free when the background allows (it did for every concept so far), else pays for an edit with a transparent background, else for an edit on flat magenta that is keyed out here; if none works the concept is marked "vector redraw needed". |
| `sheet icon\|feature\|shots [--ids …] [--out DIR]` | The review sheets for gates 3 and 4: `build/art/review/<kind>.html` and `<kind>.png`. |
| `pick icon\|feature ID` | Records the owner's choice in `brand/picks.json`, copies its art to `brand/masters/` (so exports never need the cache) and fills in the icon's alt text. |
| `export icons\|store\|web\|all [--out DIR] [--icon ID] [--feature ID] [--check]` | Every file cut from the picked art. With `--out` it writes a trial under that folder and leaves the apps alone (`--icon`/`--feature` try a concept that isn't picked); `--check` writes nothing and fails if any file differs from a fresh export. |
| `shots android\|ios [--raw DIR] [--claims voiceover,talkback] [--sizes …] [--out DIR] [--replace]` | Frames the raw captures under their captions (below). `--sizes` takes `phone`, `7in`, `10in`, `10in-land` and `wear` for Android (default `phone`), and `6.9`, `6.3` and `13` for iOS (default `6.9,6.3`). |
| `check [--out DIR]` | The brand files against `docs/DESIGN.md`, the cache and its ledger, the picks, every exported file, the screenshots. Errors exit 1. |

A trial run of the whole export, apps untouched (`--raw` takes any folder of raw captures):

```
py -3.13 tools/make_art.py layers icon icon-10
py -3.13 tools/make_art.py export all --icon icon-10 --out build/art/test-export
py -3.13 tools/make_art.py shots android --raw build/art/test-shots/android/raw --out build/art/test-export
py -3.13 tools/make_art.py check --out build/art/test-export
```

A trial is a snapshot: its `colors.xml` is the repo's at the time with the launcher colour changed, so `check --out`
reports it as different once someone edits the real `colors.xml`. Export the trial again.

## Costs, the cache and the budget

- Every paid image is kept in `tools/cache/art/<key[:2]>/<key>/` (committed): `request.json` (the request as sent,
  input images as the sha256 of their pixels), `meta.json` (when, how long, the model's token usage, the cost, the
  revised prompt; never the key) and the image (concepts and probes as WebP at quality 90; layers as PNG). The key is
  the sha256 of the request, so asking again for the same thing costs nothing. `--force` adds a new take; it never
  overwrites one.
- `tools/cache/art/ledger.jsonl` has a line per paid call with its cost, worked out from the response's token usage
  and the prices in `brand/brand.json` (`prices`, taken from OpenAI's pricing page on 2026-10-09; update them when
  OpenAI's change). `tools/cache/art/index.json` names the concepts.
- The budget guard runs before every call: a command stops before it would spend more than `--budget` (default
  `budget.run` in `brand.json`, $5), and every command stops once the ledger would pass `budget.total` ($60). A call's
  cost is guessed beforehand from the dearest similar call in the ledger, else from OpenAI's published token counts
  (high on purpose).
- Failures: a 429 waits for `retry-after`; a 5xx, a timeout or a dropped connection tries again after 2, 4, 8, 16 and
  32 seconds; any other 4xx fails that request at once (a model that refuses `input_fidelity` is asked once more
  without it); a 401 or 403 stops the run.

**Spent so far (2026-10-09): $0.224** in 19 calls: the probe ($0.034), eight icon concepts ($0.116), two
refinements of icon-04 ($0.044) and four feature concepts ($0.030). Everything since has been offline.

## Models

`brand.json`'s preference: `gpt-image-2.5-sunburst`, `gpt-image-2`, `gpt-image-1.5`, `gpt-image-1`. Concepts use the
first one the key has that the probe hasn't seen fail; transparent layers use the first one the probe saw make a
transparent background. What the probe found on 2026-10-09:

| Model | Transparent background | Custom size (1536x752) |
|---|---|---|
| gpt-image-2.5-sunburst | yes | yes |
| gpt-image-2 | no ("not supported for this model") | yes |
| gpt-image-1.5 | yes | no (1024x1024, 1024x1536, 1536x1024 only) |
| gpt-image-1 | yes | no (the same three sizes) |

The key also lists `gpt-image-1-mini`, `gpt-image-2-2026-04-21`, `gpt-image-2.5-flare` (and its dated snapshot),
`gpt-image-2.5-sunburst-2026-09-08` and `chatgpt-image-latest` (not probed: not in the preference list).

## Gate 3: the icon

Open `build/art/review/icon.html` (or `icon.png`, the same as one picture; `icon-small.png` shows every concept at 29
and 16 px, actual size and magnified). Each concept is shown as it would ship: the emblem cut out and placed on the
brand background, not as the model drew it (that's the small "as generated" picture). For each one the sheet shows:

- the icon at 180, 120, 87, 60, 40, 29 and 16 px, the sizes phones and settings screens really draw;
- the iOS shape and Android's circle, squircle, teardrop and rounded-square masks;
- the iOS dark and tinted icons and Android's themed icon (the monochrome layer);
- grey, and protanopia, deuteranopia and tritanopia (Machado 2009);
- light, dark and busy wallpapers;
- each emblem colour's contrast with the background around it, and with any emblem colour it sits on (gold bars on a
  white bubble), flagged under 3:1, and how much of the emblem stays at least a pixel thick at 29 and 16 px.

What makes a good icon for this audience: one bold silhouette that is still recognisable at 29 px; big solid shapes
rather than thin lines or many small parts; strong contrast between every part and what's behind it, not only between
the emblem and the navy; and continuity with today's icon (white headphones with gold sound bars), so players who
know the app find it.

To choose: `py -3.13 tools/make_art.py pick icon icon-NN`, then `export all` and `check`, then the follow-ups below.
If none is right, `refine icon icon-NN --note "…"` (or new motifs in `brand/prompts/icon.json`) and a new sheet.

The concepts so far, and the ranking given to the owner, are at the end of this page. The owner chose icon-03 on
9 October 2026 (`brand/picks.json`), the sturdiest shape at small sizes. Its known weak spot is the sheet's: the gold
bars sit on white at 1.41:1, so the tinted icon is stretched to keep the two apart once iOS tints it, and the bars
are worth a look in grey and on a low-vision player's phone.

## Gate 4: captions and the feature graphic

- **Feature graphic and social image:** `sheet feature` shows Play's 1024x500 feature graphic and the website's
  1200x630 social image on the plain brand background and on each feature concept, with Play's guides drawn in (the
  text area inside x 60-964, y 50-450, and the middle 220 px Play keeps clear for its play button when there's a
  video). The icon, the name and the tagline (`brand.json` `name`, `tagline`) are placed by the tool in the left column,
  white and gold, with a navy scrim behind them if the art would bring the text under 7:1.

  Four concepts were made on 9 October 2026 (`gpt-image-2.5-sunburst`, medium quality, 1536x752). Each keeps the
  icon and the words at x 60-339, y 70-429, inside Play's text area and clear of its middle band (x 402-622):

  | Concept | Feature graphic: white / gold text | Social image: white / gold | Middle band standing out at 3:1 or more |
  |---|---|---|---|
  | feature-01 waves | 18.0:1 / 12.7:1 | 11.8:1 / 8.4:1, no scrim | 2.3% |
  | **feature-02 rings** (picked) | 18.3:1 / 13.0:1 | 11.4:1 / 8.1:1, no scrim | 0.0% |
  | feature-03 night sky | 18.4:1 / 13.0:1 | needs a 65% scrim band | 0.5% |
  | feature-04 story glow | 17.5:1 / 12.4:1 | needs an 80% scrim box | 1.5% |

  feature-02, golden rings of sound spreading out from the right third, is the only one with nothing in the middle
  band (Play's play button sits on plain navy once there's a video), neither image needs a scrim, and the rings echo
  the talking circle's. It's exported as the proposal; to swap: `pick feature feature-0N`, `export store`, `export
  web` (the social image `og-v2.png` is cut from the same art), then `check`.
- **Screenshot captions:** `brand/shots.json`. Words between `*stars*` are drawn gold, the rest white, both at least
  7:1 on the navy. Play's rules: no "Free", "Best", "#1", "Top", "New" or "Sale", no calls to action, captions in
  under 20% of the picture (the band is 17.5%). Apple's: never "Android", "TalkBack" or "Google Play" in App Store
  screenshots. A caption that makes a claim ("Works with VoiceOver", "Works with TalkBack") is left out until the
  real-device screen-reader test has earned it, then added with `--claims voiceover` or `--claims talkback`.

## The screenshots

`shots` puts each raw capture on the brand background, scaled down with rounded corners and a thin outline, under its
caption (Atkinson Hyperlegible Next Bold, up to two lines, shrunk to fit). The raw captures are honest screenshots of
the app: from the emulator (`tools/store_shots.py android`, `docs/RELEASE.md`) or the Mac's simulator
(`StoreScreenshotsUITests`).

| Size (`--sizes`) | Raw captures | Framed | Layout |
|---|---|---|---|
| Play phone (`phone`) | `build/store-shots/android/raw/<name>.png` | `android/fastlane/metadata/android/en-US/images/phoneScreenshots/<name>.png`, 1080x1920 | caption band 336 px, captions 84 px (down to 64), screen at 0.8 of the width from y 360 |
| Play 7-inch tablet (`7in`) | `…/raw/tablet7/<name>.png` (1200x1920 at 320 dpi) | `…/images/sevenInchScreenshots/<name>.png`, 1080x1920 | as the phone's, with the screen at 0.9, centred |
| Play 10-inch tablet (`10in`, `10in-land`) | `…/raw/tablet10/` and `raw/tablet10-land/` (1600x2560 at 320 dpi, and turned) | `…/images/tenInchScreenshots/<name>.png` 1440x2560, and `<name>_landscape.png` 2560x1440 | band 448 px, captions 112 px, screen at 0.9 from y 480; turned, band 260 px, captions 100 px, from y 280. The two share the folder |
| Play Wear OS (`wear`) | `…/raw/wear/<name>.png`, from a Wear OS emulator | `…/images/wearScreenshots/<name>.png`, as captured | none: square, no caption, no frame (Play wants the watch's screen alone, at least 384x384) |
| App Store 6.9" (`6.9`) | `build/store-shots/ios/raw/<name>.png` | `ios/fastlane/screenshots/en-US/<name>_1320x2868.png` | band 456 px, captions 112 px (down to 84), screen at 0.82 |
| App Store 6.3" (`6.3`) | the same | `…/<name>_1206x2622.png` | the same layout, scaled |
| App Store 13" iPad (`13`) | `build/store-shots/ios/raw/ipad13/<name>.png` (iPad Pro 13-inch (M4), upright) | `…/<name>_2064x2752.png` | band 440 px, captions 128 px (down to 96), screen at 0.86, centred, from y 470 |

Play's 1080x1920 (9:16) is there because the emulator's 20:9 captures break Play's 2:1 limit. On 10 October 2026 the
phone and 7-inch sets got all eight scenes, and the 10-inch set four upright (04, 05, 07, 08) and four turned (01,
02, 03 and 06, where the wider window shows the two-pane game and Help's list beside its topic: `brand/scenes.json`).
A raw `iap_<product>.png` is copied as it is to `ios/fastlane/iap_review/<product>.png` (the in-app purchase review
screenshot). Screenshots that were in a store folder before and weren't made now are listed; `--replace` removes them
(fastlane uploads everything in the folder). Apple Watch screenshots aren't framed: `docs/WATCH.md` says how to take
them on the simulator, at the watch's own size.

## What gets exported

| Where | Files |
|---|---|
| `ios/EpicAudioGames/Resources/Assets.xcassets/AppIcon.appiconset/` | `AppIcon.png` 1024x1024 RGB, no alpha (App Store Connect refuses alpha: ITMS-90717); `AppIcon-Dark.png` (the emblem on transparent, iOS 18 dark); `AppIcon-Tinted.png` (the emblem in grey on transparent, stretched so gold and white stay apart once iOS tints them); `Contents.json` with the dark and tinted appearances |
| `…/Assets.xcassets/LaunchLogo.imageset/` | the emblem at 160 pt (`@2x` 320 px, `@3x` 480 px) for `UILaunchScreen`'s `UIImageName` and the intro |
| `android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/` | `ic_launcher_foreground.png` (108 dp canvas, the emblem 52 dp across and inside the 66 dp safe circle), `ic_launcher_background.png` (the navy gradient), `ic_launcher_monochrome.png` (white silhouette for Android 13+ themed icons: parts drawn in one colour on top of another become holes, gaps closed, specks removed), `ic_launcher.png` and `ic_launcher_round.png` (48 dp, for API 24-25) |
| `…/res/mipmap-anydpi-v26/` | `ic_launcher.xml`, `ic_launcher_round.xml`: background, foreground and monochrome |
| `…/res/drawable-*dpi/splash_emblem.png` | the emblem on a 288 dp canvas (128 dp across, inside the 192 dp circle), for the splash screen if the theme wants it rather than the launcher foreground |
| `…/res/values/colors.xml` | `ic_launcher_background` set to navy #0B1430 (the splash icon's backdrop); nothing else in the file changes |
| `android/fastlane/metadata/android/en-US/images/` | `icon.png` 512x512 32-bit (what a launcher shows of the adaptive icon: its middle 72 dp), `featureGraphic.png` 1024x500 RGB |
| `web/public/` | `favicon.ico` (16, 32, 48), `apple-touch-icon.png` (180), `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (the emblem inside the maskable safe circle), `emblem.png` (256, for the header), `og-v2.png` 1200x630, `manifest.webmanifest` |

The watch apps' icons aren't exported: they're copies. The Wear OS app's `android/wear/src/main/res/mipmap-*` are the
phone app's adaptive-icon layers and its `mipmap-anydpi-v26` XML, byte for byte (`WatchAppTest` fails until they match
again), and the Apple Watch app's `ios/EpicWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is the iPhone's
1024 image. After a new `export icons`, copy both across.

Every background is the same deterministic radial gradient (#16275E in the middle to #0B1430), with a level of noise
so it doesn't band. PNGs are written without metadata. `export --check` and `check` compare pixels, not bytes (zlib
differs between machines), so the Mac and this PC agree.

**After the first real export** (each is printed by `export` when it applies, and other work owns the files). Done
for icon-03 by 10 October 2026:

- `AndroidManifest.xml`: `android:roundIcon="@mipmap/ic_launcher_round"`.
- `export` deleted `res/mipmap/ic_launcher.xml` (the old icon's layer-list), and `res/drawable/ic_launcher_foreground.xml`
  (the old vector) is gone too. `drawable/ic_notification.xml` (the headphones glyph) stays unless the motif changes.
- `ios/scripts/render_icon.swift` (it drew the old vector icon on the Mac) is retired, with its entries in
  `project.pbxproj` and its mention in `docs/IOS.md`.
- The website's `<head>`: the icons, `manifest.webmanifest`, `og-v2.png` with `og:image:alt` (below).

Still to do, on the Mac and on phones: `fastlane ios check` and `fastlane android check`; the iOS dark and tinted icons
on a phone running iOS 18 or later, and the themed icon on Android 13 or later.

## Brand settings (`brand/`)

| File | What's in it |
|---|---|
| `brand.json` | The palette (docs/DESIGN.md's Dark tokens: `check` fails if they drift apart), the emblem's colours, the background gradient, the font files, how big the emblem sits on each platform's icon and inside which safe area, the feature graphic's and social image's layout, the models in order of preference, their prices, the budget. |
| `prompts/icon.json`, `prompts/feature.json` | The prompts: `base` with `{motif}` replaced by each motif's words, the refine and layer prompts. A changed prompt is a new request (and a new cost); the old images stay in the cache. Each motif has an `alt`, the alt text if it's picked. |
| `shots.json` | The screenshot layouts (one per size, above) and captions. |
| `scenes.json` | The scenes `tools/store_shots.py` captures, with the launch extras that set each one up, and its targets: phone, the tablets and Wear OS. |
| `previews/` | The preview video's storyboard and each store's cut (`tools/make_preview.py`). |
| `picks.json` | The picks: icon-03 (the owner's, gate 3) and feature-02 (the proposal for gate 4). |
| `masters/` | The picked art: `icon-concept.webp`, `icon-emblem.png` (the cut-out every icon comes from), `feature-art.webp`. |
| `alt-text.json` | The text alternatives below. |

The icon prompt asks for a square full-bleed navy (#0B1430) icon with an optional soft glow, one centred emblem in
gold (#FFD54F) and white filling about 60% of it, flat bold shapes with rounded ends, at most three elements, readable
at 29 px, and no text, letters, frame, rounded tile, device, people, shadows, gradients or thin lines.

## Alt text

`brand/alt-text.json` holds the text alternatives; `pick` fills in the icon's and the emblem's from the picked motif.

| Image | Where it's used | Text |
|---|---|---|
| The social image (`og-v2.png`) | the website's `<meta property="og:image:alt">` | `og`: "Epic Audio Games: audio story games you play by voice." |
| The emblem (`emblem.png`) | the website header's `<img>` | `alt=""` when the name "Epic Audio Games" is written next to it (as in the header, so a screen reader doesn't say the name twice); `emblem` when it stands alone |
| The app icon | anywhere a page shows the icon as a picture (the support page, a press kit) | `icon`: "Epic Audio Games app icon: a white speech bubble holding gold sound bars, on navy." (icon-03's) |
| The feature graphic | wherever it's shown outside Play | `featureGraphic` |
| The screenshots | the website, if it ever shows them; the store descriptions say the same in words | `screenshots.<name>`: the caption, then what the screen shows |
| The intro's logo in the apps | not from this file: it's one accessibility element, "Epic Audio Games" (docs/DESIGN.md) | |

Neither App Store Connect nor the Play Console asks for alt text for listing images, so the listings' own text must
say what matters (`docs/STORE_LISTING.md`). An image that only decorates (the gradient, the emblem beside the name)
gets an empty `alt`.

## The icon concepts (2026-10-09)

All ten were made with `gpt-image-2.5-sunburst` at medium quality, 1024x1024; icon-09 and icon-10 are refinements of
icon-04 ("Make the white headband as thick as the ear cups' rounded ends"). Every one cuts out cleanly here (the local
method), and every emblem colour is at least 10:1 against the navy around it. "Thick" is how much of the emblem
stays at least a pixel thick at 29 px (and at 16 px).

The ranking given to the owner before gate 3, where the owner chose icon-03 (sixth here):

| | Concept | Motif | Thick at 29 (16) px | Why |
|---|---|---|---|---|
| 1 | icon-10 | white headphones around a gold speech bubble (refined) | 64% (37%) | Keeps today's white headphones with something gold between the ear cups, and says what the games are: you listen, and you talk back. The bubble is one big solid gold shape that still reads at 29 px, and gold never touches white. Weak spots: the headband is still thinner than the ear cups, the bubble's tail is a thin point, and the gap between bubble and cups closes up at 16 px. |
| 2 | icon-09 | the other take of the same refinement | 64% (38%) | Nearly the same as icon-10, with a slightly smaller bubble. |
| 3 | icon-07 | a white microphone under gold headphones | 60% (33%) | The boldest new silhouette. But the headphones turn gold (today they're white), it reads like a podcast or call-centre app, and the microphone's stand and base are thin. |
| 4 | icon-01 | today's icon, redrawn on navy | 54% (21%) | The most continuity and a safe fallback, but the three bars are thin and blur at 16 px, and it says "listen" without "talk". |
| 5 | icon-04 | the original of icon-09 and icon-10 | 63% (39%) | A thinner headband than its refinements. |
| 6 | icon-03 | gold sound bars in a white speech bubble | 88% (77%) | The sturdiest shape at small sizes, but its gold bars sit on white at 1.41:1, so they vanish in grey, in the tinted icon and for many low-vision players, leaving a plain white bubble that looks like a messaging app. No headphones either. |
| 7 | icon-05 | a gold dot with white sound arcs | 39% (15%) | The everyday "broadcast" or "wireless" symbol: not ours, and the arcs are thin. |
| 8 | icon-08 | gold bars forming a circle under a white band | 35% (5%) | Seven thin bars that blur into a gold smudge at 29 px. |
| 9 | icon-06 | a gold waveform ring around a white circle | 36% (7%) | A spiky ring that reads as a gear or a sun, with no sense of sound. |
| 10 | icon-02 | headphones whose band is a gold wave | 51% (25%) | The wave reads as a crown or a flame, and the headphones get lost. |

With icon-03 picked, this refinement wasn't needed. Were icon-10's idea ever wanted after all, one more at high
quality should fix its weak spots first (the dry run puts it at about $0.26 a take, on the high side: medium-quality
takes have cost about a fifth of their estimates):

```
py -3.13 tools/make_art.py refine icon icon-10 --n 2 --quality high --note "Make the white headband as thick as the ear cups. Leave a clear navy gap between the speech bubble and each ear cup. Give the bubble a short, wide, rounded tail."
```
