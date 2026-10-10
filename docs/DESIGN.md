# Design and accessibility

Epic Audio Games is made for blind and partially sighted players first, and for everyone else as well. Both apps
(Android and iPhone) follow this page, in parity. It is the source of truth for colours, type, layout, wording and
how the screen readers behave; `docs/IOS_PARITY.md` lists the few places the two apps differ on purpose.

The standards: Apple's Human Interface Guidelines (Accessibility) and Google's Android accessibility guidance, with
WCAG 2.2 as the yardstick: AAA contrast (7:1) for all text, at least 3:1 for everything else that carries meaning,
text that scales to 200% and beyond, nothing shown by colour alone, nothing that moves when motion is turned off.

## Principles

1. **Audio first, screen second.** The game speaks; the screen shows the same words. Nothing important is only on
   screen, and nothing the game says is announced a second time by the screen reader.
2. **One button always works.** Tapping the picture (the talking circle), Magic Tap on iOS, the headphones' button
   and the notification's button all do the next sensible thing: skip, talk, stop listening, or carry on.
3. **The microphone never surprises anyone.** It opens with a sound (the listening earcon) and a haptic tick, never
   with a spoken announcement (the recogniser would hear it). With a screen reader on it doesn't open by itself
   unless the player asks for that in Settings.
4. **Plain words.** Sentence case everywhere (no ALL CAPS), short labels, a visible label that matches what the
   screen reader says (so Voice Control and Voice Access work by saying it).
5. **Respect the phone's settings** (dark mode, increased contrast, bold text, text size, reduced motion and
   transparency, button shapes) and offer our own on top for players who don't want to change the whole phone.

## Structure

```
Cold start: system splash (navy + logo) → Intro (sting; once per launch; skippable; off in Settings)
  → Onboarding (first run; reopenable from Help and Settings)
  → Tabs (bottom bar; hidden while a game is open)
     1 Games     heading "Games"     game cards → the game (full screen) · "Get <pack>" → the store sheet
     2 Shop      heading "Shop"      every pack, grouped by game · Restore purchases
     3 Help      heading "Help"      topics → topic page (Listen) · "Show the welcome again" · contact
     4 Settings  heading "Settings"  Sound and voice · Microphone · Appearance · Transcript · Privacy · Help and about
                                     (an Account section comes later, with sign-in)
Game: header (Back · title · ⋮ Start again / More stories and levels / How to play)
  over it: Paused (Carry on · How to play · Leave game) · end panel · store sheet · help sheet · microphone dialog
```

- Android keeps switching screens on state in `App()` (no Navigation-Compose); iOS uses `TabView`.
- "More stories" from a game card, the game's ⋮ menu or a locked chapter end opens the **store sheet for that one
  game** (the same rows as the Shop tab), never a tab switch. Focus returns to where it was when the sheet closes.
- Android Back: a Help topic → the Help list → Games → leaves the app. In a game: leaves the game (its place is
  saved). Sheets close first. iOS: the tab bar, the topic page's back button, and Escape (two-finger scrub), which
  closes sheets and topic pages and leaves a game.
- On screens 600 dp and wider (Android 16 ignores the portrait lock there), content is at most 640 dp wide, centred.

### Test identifiers (the same on both apps)

| Screen | Android composable | iOS view | Identifiers |
|---|---|---|---|
| Intro | `IntroScreen` | `IntroView` | `intro` |
| Onboarding | `Onboarding` | `OnboardingView` | `onboarding-welcome`, `-mic`, `-comfort`, `-screen-reader`, `-ready`; `onboarding-next`, `onboarding-back`, `onboarding-skip`, `analytics-off` |
| Tabs | `MainTabs` | `MainTabs` | `tab-games`, `tab-shop`, `tab-help`, `tab-settings` |
| Games | `HomeScreen` | `HomeView` | `games-heading`, `game-<id>`, `packs-<id>` |
| Shop | `ShopScreen` | `ShopView` | `shop-heading`, `shop-game-<id>`, `pack-<packId>`, `buy-<packId>`, `restore` |
| Store sheet | `StoreSheet` | `StoreSheet` | `store-sheet`, `store-close` |
| Help | `HelpScreen`, `HelpTopicPage`, `HelpSheet` | `HelpView`, `HelpTopicPage`, `HelpSheet` | `help-heading`, `help-topic-<id>`, `help-listen` |
| Settings | `SettingsScreen`, `LicencesPage` | `SettingsView`, `LicencesPage` | `settings-heading`, `setting-<key>` |
| Game | `GameScreen` | `GameView` | `talking-circle` (kept), `game-menu`, `end-heading`, `end-next`, `end-get`, `end-again`, `end-back`, `paused-carry-on`, `paused-help`, `paused-leave` |

Android sets `testTagsAsResourceId = true` at the root so UI tests and screenshot scripts can find these.

## Colour

Tokens have the same names on both apps (`ui/theme/Tokens.kt`, `UI/Design/Tokens.swift`). The brand is the website's
navy and gold.

Themes: **Match my phone** (default: Light or Dark from the system), **Light**, **Dark**, **High contrast** (black,
white and yellow). When the phone asks for more contrast (iOS Increase Contrast, `colorSchemeContrast ==
.increased`; Android 14+ `UiModeManager.getContrast() >= 0.5`, or high-contrast text): Light becomes **Light +
increased contrast**, and Dark becomes **High contrast**.

| Token | Dark | Light | High contrast | Light + increased contrast | Used for |
|---|---|---|---|---|---|
| background | #0B1430 | #F3F5FB | #000000 | #FFFFFF | screens |
| surface | #16275E | #FFFFFF | #000000 | #FFFFFF | cards, bubbles, chips, text field |
| surfaceRaised | #1B2D66 | #FFFFFF | #000000 | #FFFFFF | headers, tab bar, sheets, end panel |
| replySurface | #2E2A12 | #FFF3C4 | #000000 (2 dp yellow border) | #FFF3C4 | "You said" bubbles |
| text | #F6F8FF | #0B1430 | #FFFFFF | #000000 | all body text |
| textMuted | #C9D2F0 | #3B4566 | #FFFFFF | #000000 | secondary text, placeholders |
| heading | #FFD54F | #16275E | #FFFF00 | #0B1430 | headings; links (always underlined) |
| primary / onPrimary | #FFD54F / #1A1400 | #16275E / #FFFFFF | #FFFF00 / #000000 | #0B1430 / #FFFFFF | primary buttons, mic, tab indicator |
| accent (never text) | #FFD54F | #8A6100 | #FFFF00 | #0B1430 | current-line bar, speaking ring |
| outline | #8E9CCB | #6B7699 | #FFFFFF | #000000 | 2 dp borders: chips, field, secondary buttons |
| outlineSubtle (decorative) | #2C3D7A | #D5DAEA | #FFFFFF | #000000 | bubble edges, dividers (2 dp in HC and LI) |
| success | #8FE3B0 | #0F5C33 | #7CFF9B | #0B4D2A | "Installed", "Microphone allowed" — always with an icon |
| error | #FFB4AB | #A4161A | #FF9E9E | #8B0000 | failures — always with an icon and words |
| ringSpeaking / ringListening / ringIdle | #FFD54F / #8FE3B0 / #8E9CCB | #8A6100 / #0F5C33 / #6B7699 | #FFFF00 / #7CFF9B / #FFFFFF | #0B1430 / #0B4D2A / #000000 | the talking circle (plus icon, words and ring style) |
| highlightBg / highlightText | #FFD54F / #0B1430 | #16275E / #FFFFFF | #FFFF00 / #000000 | #0B1430 / #FFFFFF | the word being spoken |
| focus | #FFD54F | #16275E | #FFFF00 | #000000 | 3 dp keyboard focus ring |
| progressFill / progressTrack | #FFD54F / #3A4A86 | #16275E / #C9CFE3 | #FFFF00 / #000000 (2 dp white border) | #0B1430 / #FFFFFF (2 dp black border) | download bar, 8 dp tall |
| scrim | background, 100% | background, 100% | 100% | 100% | Paused, Loading — always opaque: text showing through behind the buttons is hard to read with low vision |

Contrast (WCAG 2.x relative luminance; minimum in brackets). Both apps have a unit test with these pairs.

| Pair | Dark | Light | HC | Light+IC |
|---|---|---|---|---|
| text / background (7) | 17.10 | 16.65 | 21.00 | 21.00 |
| text / surface (7) | 13.32 | 18.15 | 21.00 | 21.00 |
| text / surfaceRaised (7) | 12.26 | 18.15 | 21.00 | 21.00 |
| text / replySurface (7) | 13.59 | 16.31 | 21.00 | 18.87 |
| textMuted / background, surface, surfaceRaised (7) | 12.07, 9.39, 8.65 | 8.64, 9.42, 9.42 | 21 | 21 |
| textMuted / replySurface (7) | 9.59 | 8.47 | 21 | 18.87 |
| heading / background, surfaceRaised (7) | 12.86, 9.22 | 12.96, 14.13 | 19.56 | 18.15 |
| onPrimary / primary (7) | 13.01 | 14.13 | 19.56 | 18.15 |
| highlightText / highlightBg (7) | 12.86 | 14.13 | 19.56 | 18.15 |
| success / surface (7) | 9.28 | 8.08 | 16.63 | 9.96 |
| error / surface, surfaceRaised (7) | 8.32, 7.66 | 7.75, 7.75 | 10.64 | 10.01 |
| outline / background, surface (3) | 6.71, 5.23 | 4.12, 4.49 | 21 | 21 |
| accent / surface (3) | 10.02 | 5.54 | 19.56 | 18.15 |
| rings speaking, listening, idle / background (3) | 12.86, 11.91, 6.71 | 5.08, 7.41, 4.12 | 19.56, 16.63, 21 | 18.15, 9.96, 21 |
| highlightBg / surface (3) | 10.02 | 14.13 | 19.56 | 18.15 |
| progressFill / progressTrack (3) | 5.94 | 9.10 | 19.56 | 18.15 |

**Rule:** text never takes an alpha. No `.copy(alpha = …)` / `.opacity()` on a text colour; the contrast test and
review enforce it. (The old design's pale "words still to come" were ink at 35%: 1.96:1.)

## Type

Atkinson Hyperlegible Next (Braille Institute; SIL Open Font License 1.1), static Regular 400, Bold 700 and
ExtraBold 800 files, shipped unmodified with the licence (`content/app/licences/OFL-AtkinsonHyperlegibleNext.txt`,
shown under Settings › Licences). Settings › Font › "Phone's font" uses Roboto / SF at the same sizes.

| Token | Base size (sp / pt) | Weight | Line height | iOS scales like | Used for |
|---|---|---|---|---|---|
| display | 34 | ExtraBold | 1.2 | .largeTitle | intro wordmark |
| title | 30 | Bold | 1.25 | .largeTitle | tab headings, onboarding and topic headings |
| headline | 22 | Bold | 1.3 | .title2 | section headings, end and pause headings, sheet titles |
| itemTitle | 20 | Bold | 1.3 | .title3 | game and pack titles, help list items, game header |
| transcript | 20 | Regular | 1.5 | .body | transcript lines and replies |
| body | 18 | Regular | 1.45 | .body | paragraphs |
| label | 18 | Bold | 1.25 | .body | buttons, chips, status line |
| speaker | 16 | Bold | 1.3 | .subheadline | speaker names, "You", badges |
| secondary | 16 | Regular | 1.4 | .callout | download sizes, notes, setting hints |
| tab (Android) | 14 | Bold | 1.2 | — | navigation bar labels (iOS uses the system tab bar) |

- Nothing smaller than 16 at 100% (tab labels 14). Sentence case. No `maxLines` anywhere except the one-line answer
  field, and no Dynamic Type caps.
- **Bold Text** (iOS `legibilityWeight == .bold`; Android `Configuration.fontWeightAdjustment`, API 31+): Regular →
  Bold, Bold → ExtraBold.
- **App text size** Standard / Large / Larger multiplies the base sizes by 1.0 / 1.15 / 1.3; the system's own scaling
  (Android's non-linear font scale, iOS Dynamic Type) applies on top. Android line heights in `em`.
- **Compact game layout** at accessibility sizes (iOS `dynamicTypeSize.isAccessibilitySize`; Android font scale
  ≥ 1.6): the game title moves to the top of the transcript as a heading, the circle shrinks to 88, and the answer bar
  stacks into two rows (Send and Talk show words).
- Touch targets at least 48 dp (Android) and 48 pt (iOS).

## Everywhere

- **Theme provider** reads: the theme setting, system dark mode, system contrast, Bold Text, Reduce Motion (iOS
  `accessibilityReduceMotion`; Android `!ValueAnimator.areAnimatorsEnabled()`; or the app's own switch), iOS Reduce
  Transparency, Button Shapes (text buttons get an underline) and Differentiate Without Colour (states always carry an
  icon and words anyway). Status bar icons follow the theme.
- **Headings:** every screen title is a level-1 heading, every section a level-2 (iOS `.isHeader` +
  `.accessibilityHeading(.h1/.h2)`; Android `heading()`).
- **Status messages** (purchase done, download finished or failed, restored, microphone allowed): Android shows them
  as visible text with `liveRegion = Polite` (and `paneTitle` on sheets and overlays; `announceForAccessibility` is
  deprecated in Android 16); iOS posts a queued `AccessibilityNotification.Announcement`. **Never while the mic is
  listening.**
- **Focus:** after the intro or onboarding, focus goes to the "Games" heading; when the end panel or the Paused
  overlay appears, focus moves to its heading (300 ms after it appears). A manual tab switch leaves focus on the tab.
- **Keyboard:** a visible 3 dp focus ring on everything focusable.

## Tab bar

- Android: Material 3 `NavigationBar` with four items, labels always shown, filled icon when selected and outlined
  when not (so the state isn't colour alone): Headphones, Storefront, HelpOutline, Settings. TalkBack should read
  "Selected, Shop, Tab, 2 of 4" (`selectableGroup`, `Role.Tab`); if the position isn't read, add `collectionInfo` /
  `collectionItemInfo`. If labels clip at 200% text, use a custom bar with the same semantics.
- iOS: `TabView(selection:)` with `.tabItem { Label(…, systemImage: "headphones" / "bag" / "questionmark.circle" /
  "gearshape") }` (iOS 17: no `Tab` struct). The system gives "tab, 2 of 4" and the Large Content Viewer.

## Games

- Heading "Games", then "Put on your headphones, listen, and answer out loud."
- Each card has two separate actions:
  1. **The card itself** (cover, title, blurb, "Free: …", an "In progress" badge with icon and words, and a visible
     "Play ›" or "Carry on ›") opens the game. Read as one element: "The Werewolf. In progress. <blurb>. 5 stories
     free." with the action label "Carry on" (Android `onClickLabel`; iOS the button's name), and a custom action
     "More stories and levels" when not every pack is installed. iOS input labels: the title and "Play <title>".
  2. **"Get 45 more mysteries"** (only for games with packs): accessible name "Get 45 more mysteries for The
     Werewolf"; opens the store sheet. With everything installed it becomes plain text: "All packs installed".
- Covers at most 180 tall; hidden at accessibility text sizes.
- Opening a game shows "Opening The Werewolf" (Android live text; iOS announcement).

## Game

- Header (surfaceRaised): Back (48), the title (itemTitle, wraps), ⋮ (48). The menu: Start again; More stories and
  levels (opens the store sheet; the game pauses); How to play (opens the help sheet on "Playing with your voice";
  the game pauses). Privacy and Support live in Settings.
- When the game opens, focus moves to the circle after 300 ms, with no announcement.
- **The talking circle** (128; 88 in the compact layout): the cover inside a ring, with a badge icon in the middle.
  - Speaking: ringSpeaking, pulsing (not with Reduce Motion), skip badge.
  - Listening: ringListening, 4–14 wide following the mic level (a steady 10 with Reduce Motion), mic badge.
  - Waiting for an answer: ringIdle, dashed, 3 wide, outlined mic badge.
  - At an end: decorative, no semantics.
  - Its name and state come from one shared function, `CircleAction.of(paused, speaking, listening, end, ask,
    micAllowed, micWorks)`, used for the circle, the notification's button and Magic Tap:

    | Action | Name | State |
    |---|---|---|
    | Carry on | "Carry on" | "Paused" |
    | Skip | "Skip" | "Speaking" |
    | Stop listening | "Stop listening" | "Listening" |
    | Talk | "Talk" | "Your turn" |
    | Microphone refused | "Talk (the microphone is off)" | "Your turn" |
    | No speech recognition | "Talk (speech recognition isn't available)" | "Your turn" |
    | Nothing to do yet | "Talk", disabled | "Wait for the question" |

    Android: `role = Button` + `stateDescription`. iOS: `accessibilityValue`, keeping `.startsMediaSession` (so
    VoiceOver stays quiet after the tap), input labels "Skip", "Talk", "Picture". A tap with the microphone refused
    goes to the same permission path as the mic button.
- Status line under the circle (label style, wraps, not a live region): "Tap the picture to skip", "Listening…",
  "“<partial words>”", "Your turn! Tap the mic to talk", "Your turn!", "Paused".
- **Transcript:**
  - A game line: a surface bubble (radius 16); the speaker's name in bold above it (hidden for the narrator, or when
    "Show who's speaking" is off — the name stays in what the screen reader reads); the words in the transcript
    style. The line being spoken has a 4 dp accent bar on its leading edge and an accent border.
  - **Highlight words as they're spoken** (on by default): only the current word is marked (highlightBg /
    highlightText). Words still to come are shown at full contrast — or, with **Show the whole line at once** off,
    hidden but keeping their space, so nothing jumps.
  - Each line is one element: "Gribbo: …". Lines are never announced as they appear: the game is already saying them.
  - The player's reply: right-aligned on replySurface with a visible "You" label; read as "You said: …".
  - Notes ("Welcome back!"): centred, secondary style.
  - Without a screen reader the transcript follows the newest line (instantly with Reduce Motion). With a screen
    reader on it only scrolls when answer chips, a reply or the end panel appear, so nothing moves under the
    player's finger.
- **Answer chips:** at least 48 tall, surface fill, 2 dp outline, label style. The group is a heading "Options" and a
  collection; each chip is a button named by its words.
- **Answer bar:** text field labelled "Type an answer"; Send (48); Talk / mic (56; primary; while listening the
  listening colour with a stop icon; refused: an outlined mic-off icon). iOS input labels "Talk", "Microphone",
  "Mic". Compact layout: the field gets a row of its own.
- **End panel** (surfaceRaised): heading "Chapter complete" / "Game over" / "The end", the end's title and any
  explanation, then full-width buttons: Next chapter (primary); Get <pack> (primary, with "What happens next is in
  …"); Play again / Try again; Back to games. Android `paneTitle` = the heading. Focus moves to the heading.
- **Paused overlay:** an opaque scrim, heading "Paused", buttons "Carry on"
  (primary, play icon), "How to play", "Leave game". A tap anywhere else carries on (pointer only; not exposed to the
  screen reader). Android `paneTitle` "Paused"; iOS `.isModal`; Magic Tap carries on.
- **Help sheet:** a Help topic page in a full-height sheet with "All help topics" and "Close".

## Shop and the store sheet

- Shop: heading "Shop", then "One-time purchases. No ads and no subscriptions. Packs download once, then play
  offline." Each game with packs is a level-2 section (with a small decorative cover).
- A pack row: title (itemTitle; level-3 heading on iOS), description, "15 MB download", then its state — always words
  and an icon, never colour alone:
  - Installed: check icon, "Installed".
  - Downloading: the 8 dp bar (value "N percent"), visible "Downloading, 40%"; the live/announced version ("45 more
    mysteries: downloading, 50%") only changes at 0 / 25 / 50 / 75 %.
  - iOS only: "Installing…"; "Waiting for Wi-Fi" with "Download now"; "Waiting for a connection".
  - Bought but not on this phone: "Bought" and "Download 45 more mysteries".
  - Pending: clock icon, "Payment pending", "Waiting for the payment to be approved."
  - For sale: primary button "Buy for £1.99" (the store's own price text). Its accessible name starts with the visible
    words, then the context: "Buy for £1.99: The Werewolf, 45 more mysteries". While the price loads: "Get" with a
    spinner, named "Get The Werewolf, 45 more mysteries, loading the price".
  - Failures: error icon and words under the row, live / announced.
- Then: store messages as status text; "Restore purchases" (secondary) with "Bought a pack on another phone? Restore
  it here."; "Payments are handled by Google Play" / "by the App Store".
- Showing the Shop tab re-reads purchases, at most once a minute.
- The store sheet: heading "More from <game>", the same rows, messages and Restore, and a "Close" button. Android
  `paneTitle`, fully expanded; iOS a large detent at accessibility sizes.
- A pack installing while the Shop or the sheet is showing plays the success sound.

## Help

- The list: heading "Help"; a row per topic (title and a one-line summary); "Show the welcome again"; Contact.
- A topic page: the heading, a **Listen / Pause** button (plays the topic in Jessica's voice, with the words
  highlighted as they're read; Android state "Playing"; iOS `.startsMediaSession`, Magic Tap toggles it; hidden when
  the clip isn't in the build), then the text: paragraphs, numbered steps, links (open the browser) and email.
- With a screen reader on, Listen starts 400 ms after the tap, so the button's own feedback finishes first.
- Topics: Getting started · Playing with your voice ("repeat", "stop") · Using VoiceOver / Using TalkBack · Typing and
  choosing answers (with keyboard shortcuts) · Pausing, repeating and leaving · Packs and purchases · Headphones and
  the lock screen · Using a watch · Text size and colours · Contact and privacy.
- The text comes from `content/app/app.json`, built from `tools/app_text.toml` by `tools/app_audio.py`: the same
  words are shown and spoken. Platform-specific paragraphs say `ios` or `android`. There is no global spoken "help"
  command: "help" is a real answer in Noodle Rush.

## Settings

One scrolling page with level-2 sections, the most useful for blind players first:

1. **Sound and voice:** Voice speed (Slower / Faster buttons, 0.75 / 1 / 1.25 / 1.5 / 1.75 / 2, the value as words —
   "1.25 times" — and "Play a sample"); Play the intro sound; Listening sounds; Vibrate when listening starts; Music
   volume (Off / 25 / 50 / 75 / 100 %; "Some scenes have their music mixed in and stay as they are"); Time to answer
   (Normal / Longer / Longest).
2. **Microphone:** "Open the microphone by itself": Not when a screen reader is on (default) / Always / Never; a status
   line ("The microphone is allowed" / "The microphone is off") with "Allow microphone" or "Open phone settings".
3. **Appearance:** Theme (Match my phone / Light / Dark / High contrast, with swatches); Text size (Standard / Large /
   Larger, with a preview); Font (Atkinson Hyperlegible, easier to read / Phone's font); Reduce motion (when the phone
   already has it on: shown on and disabled, "On in your phone's settings").
4. **Transcript:** Highlight words as they're spoken; Show the whole line at once; Show who's speaking.
5. **Privacy:** "Share usage data" (on by default) with "Helps us see which games and screens people use, under a
   random ID. Never your name, email or voice, never what you say or type, and nothing about accessibility
   settings."; "Delete my usage data"; Privacy policy.
6. **Help and about:** How to play; Show the welcome again; Support; Accessibility statement; Licences; Version.

Later, with sign-in: an Account section between Transcript and Privacy (`settings.account.*` keys are reserved).

Controls: Android whole-row `toggleable(role = Switch)` and `selectableGroup()` + `selectable(role = RadioButton)`;
iOS `Toggle` and a choice group of buttons with the `.isSelected` trait.

### Settings keys (the same strings on both apps)

Android `SharedPreferences("settings")`; iOS `UserDefaults.standard` (launch arguments override them in UI tests).

| Key | Type | Default | Values |
|---|---|---|---|
| `settings.theme` | string | `system` | system, light, dark, contrast |
| `settings.textScale` | float | 1.0 | 1.0, 1.15, 1.3 |
| `settings.font` | string | `atkinson` | atkinson, system |
| `settings.reduceMotion` | bool | false | in effect = the system's setting OR this |
| `settings.highlightWords` | bool | true | |
| `settings.wholeLine` | bool | true | |
| `settings.speakerNames` | bool | true | visual only |
| `settings.introSound` | bool | true | false also skips the intro screen |
| `settings.listeningSounds` | bool | true | |
| `settings.listeningHaptics` | bool | true | |
| `settings.voiceSpeed` | float | 1.0 | 0.75, 1, 1.25, 1.5, 1.75, 2 |
| `settings.musicVolume` | float | 1.0 | 0, 0.25, 0.5, 0.75, 1 |
| `settings.answerTime` | string | `normal` | normal (6 s), longer (10 s), longest (15 s) |
| `settings.micAuto` | string | `notWithScreenReader` | notWithScreenReader, always, never |
| `settings.micPrimed` | string | `unasked` | unasked, allowed, declined |
| `settings.onboardingVersion` | int | 0 | 1 once finished or skipped |
| `settings.welcomePlayed` | bool | false | |
| `settings.analytics` | bool | true | |

## Intro

- The system splash (Android SplashScreen API; iOS `UILaunchScreen`) is navy with the logo; the intro screen takes
  over in the same place: the logo in a circle and the "Epic Audio Games" wordmark (display style), which fades in
  over 300 ms (at once with Reduce Motion). Navy in every theme.
- One accessible element, "Epic Audio Games", with the action "Skip intro" (a tap, Magic Tap or Escape skips).
- The sting starts as it appears, or 700 ms later with a screen reader on (so its label is read first); no
  announcement is posted. The intro ends 300 ms after the sting, or after 2.5 s without one.
- Only on the first launch of the process, and only with "Play the intro sound" on. Then onboarding (first run) or
  Games, with focus on the heading.

## Onboarding

Explicit Back / Next / Skip buttons (no swipe pager), "Step 2 of 4" as words, focus on each page's heading.

1. **Welcome:** the welcome text and Listen. The clip plays by itself once, only when no screen reader is on. One
   plain line: "We collect usage data under a random ID to improve the games — never what you say, and nothing about
   accessibility settings." with a "Turn off" button (`analytics-off`).
2. **Answer out loud:** why the app needs the microphone (and, on Android 13+, notifications), "Allow microphone" (the
   system asks) / "Not now"; the result as live text: "The microphone is on." or "No problem: you can tap or type,
   and allow it later in Settings." Sets `settings.micPrimed`.
3. **Make it comfortable:** Theme and Text size, plus "More in Settings".
4. **Playing with VoiceOver / TalkBack:** only when a screen reader is on (how to talk, skip and pause with gestures and
   the headphones' button).
5. **You're ready:** "Start playing".

Afterwards a game asks for the microphone on opening only if `micPrimed` isn't `declined`; the mic button always asks.

## Sounds, haptics and the microphone

- **Listening started** (rising, about 150 ms) plays every time the microphone opens — by itself, from the mic
  button, the circle, Magic Tap or the headphones' button — with a haptic tick (settings `listeningSounds`,
  `listeningHaptics`). The recogniser never hears it: on iOS, microphone audio recorded before the sound has been
  heard out is dropped; on Android the recogniser starts after it.
- **Listening stopped** (falling) plays when the recogniser ends the listen or the player turns the mic off — not
  when a new turn, typing, a pause or leaving stops it.
- **Success** plays when a pack finishes installing while the Shop or the store sheet is showing.
- There is never a spoken "Listening" announcement: the sound is the cue.
- **The sting** plays on a cold start: on iOS through the ambient session (it respects the silent switch and never
  stops other apps' audio; skipped when other audio is playing); on Android without taking audio focus (skipped when
  music is playing).

## Usage data

Progression analytics under a random install ID (pseudonymous — never called "anonymous") go to our own server
(`/api/events`), on by default, off in Settings › Privacy. The whitelist of events and properties is
`web/analytics/events.json` (inside `web/` because that's all Railway uploads); both apps' tests and the server enforce
it. **Never sent:** anything the player says or types, transcripts, audio, whether a screen reader is on, any accessibility or
comfort setting, which help topic was read, device model, advertising IDs, location.

## Tablets, foldables, Chromebooks, Mac and Vision

The same apps run on iPad (iPadOS 17+), Android tablets, foldables and Chromebooks; the iPad app also runs on
Apple-silicon Macs and Apple Vision Pro as "Designed for iPad".

- **Width classes** (Android `currentWindowAdaptiveInfo()` from material3-adaptive; iOS `horizontalSizeClass` plus the
  window's width): compact under 600, medium 600–839, expanded 840 and over (dp / pt).
- **Navigation:** compact = the bottom tab bar; medium and expanded = a navigation rail on Android
  (`NavigationSuiteScaffold` switches automatically) and the system's iPad tab bar / sidebar on iOS. Same four
  destinations, same order, same names.
- **Reading measure:** text, lists and settings at most 640 wide, centred. The Games tab shows cards in a grid on
  expanded widths (2 columns, each at most 480).
- **The game on wide windows** (expanded, or medium in landscape): two panes. Left (about 40%): header, the talking
  circle, the status line, the answer chips and the answer bar. Right: the transcript. The focus order is the same as on
  a phone (header, circle, transcript, answers). On compact widths it's the phone layout.
- **Help on wide windows:** list and detail side by side (Android `ListDetailPaneScaffold`; iOS `NavigationSplitView`
  for the Help tab on regular width). Settings stays one column.
- **Orientation:** phones stay portrait; tablets, foldables and desktops use every orientation and any window size
  (split screen, Stage Manager, freeform windows). Layouts reflow at every size; the game keeps playing when its window
  isn't focused.
- **Keyboard** (common on iPads, Chromebooks and Macs): everything reachable with Tab and the arrow keys, with the
  visible focus ring. Shortcuts: Space = the one button (skip / talk / stop listening / carry on) when the answer field
  doesn't have focus; Return in the field sends; Escape pauses a game, or closes a sheet; Ctrl/⌘ + 1–4 switch tabs.
  iOS lists them in the ⌘-hold overlay (`.keyboardShortcut`).
- **Pointer:** hover states on every button (iOS `.hoverEffect`), and the mouse can do everything a finger can.
- **Store art:** iPad 13" screenshots (2064x2752), Play 7" and 10" tablet screenshots, and a Chromebook-friendly
  landscape shot.

## Watches

- **Already today, no watch app needed:** the phone game publishes its controls to the system (Now Playing on iPhone,
  a media session on Android). Apple Watch's Now Playing and Wear OS's media controls show the game's title and
  cover, and their play/pause button is the game's one button: skip, talk, stop listening or carry on. Help explains
  this ("Using a watch").
- **The Apple Watch app and the Wear OS app** (companions; the phone plays the audio and listens, since watches have no
  speech recognition for apps and the games are about 190 MB): the game's title, its state in words ("Speaking",
  "Your turn", "Listening…", "Paused"), one big button named by `CircleAction` (the same names as on the phone), a
  "Pause" button, and a strong haptic when the microphone opens (a different one when listening stops) — the cue for a
  player who can't hear the listening sound. Large text, high contrast, VoiceOver / TalkBack on the watch, no colour-
  only states. Apple Watch talks to the phone with WatchConnectivity; Wear OS with the Wearable Data Layer.
- **Store art:** Apple Watch screenshots; Wear OS screenshots (round, 384x384 or larger).

## Not planned

Apple TV and Google TV (no speech recognition for apps, and the remote's mic belongs to the system), CarPlay and
Android Auto (games aren't allowed in car apps, and talking games while driving aren't safe).

## Checking on real phones

Before claiming VoiceOver / TalkBack support in a store listing, all of these pass on a real device:

- A whole game of Noodle Rush with VoiceOver and the screen curtain on; the same with TalkBack.
- With a screen reader on, the microphone never opens by itself (default setting); Magic Tap, the headphones' button
  and TalkBack's two-finger double tap (if it reaches the app's media session) skip, talk, stop listening and carry on.
- 50 automatic listens at full volume through the speaker, in a quiet room: no phantom words from the listening
  sound; "yes" said straight after the sound is heard.
- The listening sounds over AirPods and an Android Bluetooth headset.
- Android with Google's recogniser (Speech Services by Google): only the game's sounds as the mic opens, as a silent
  listen ends and at each silent restart with Longest. The app mutes notification sounds while it listens (Google plays
  its own sounds as notification sounds) and gives them back a moment after (`adb logcat -s RecognizerBeep`). Google's
  sound still follows the game's on a phone whose notification volume is its ringer's (many from before Android 14:
  the app leaves the ringer alone, and logs it) and with another maker's recogniser: check one of each.
- The sting with the silent switch on, and with music playing in another app.
- Voice speed from 0.75 to 2×: the highlight keeps up with the voice.
- 200% text (Android) and the largest accessibility size (iOS) on a small phone; Bold Text; High contrast and
  Increase Contrast; Reduce Motion and Remove animations.
- Voice Control and Voice Access: every button can be pressed by saying its visible label.
- Switch Control / Switch Access and a hardware keyboard reach everything.
- A sandbox purchase, download and restore on both stores.
- Usage data arriving at the server, stopping when switched off, and deleted by "Delete my usage data".
