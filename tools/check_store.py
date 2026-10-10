"""Checks both store listings offline, as `fastlane ios check` and `fastlane android check` do, on any machine.

The fastlane lanes need Ruby and fastlane (the Mac); this needs only Python's standard library, and ffprobe when there
are App Previews. Text files are read as git stores them (a Windows checkout's CRLF is read as LF), so the counts are
the ones the Mac uploads.

Errors (the exit code is 1 if there are any):
  - a listing text over its store's limit, or a required one missing; iOS keywords over 100 bytes; the Play short
    description not exactly 80 characters, or with a newline at the end (supply sends the file as it is);
  - App Store text that names another platform (Android, TalkBack, Google: Apple's guideline 2.3.10);
  - a claim the apps can't make yet: VoiceOver or TalkBack in a public listing before the real-device test
    (docs/DESIGN.md; --claims voiceover,talkback once it has passed), or "no tracking", "no account", "data not
    collected" or "anonymous", which the usage data has made untrue;
  - images the stores refuse: sizes, an alpha channel, file sizes, an App Store icon with alpha (ITMS-90717);
  - App Previews outside Apple's specs (ffprobe);
  - PrivacyInfo.xcprivacy and app_privacy_details.json disagreeing, or an App Privacy value Apple doesn't have;
  - the usage-data whitelist (web/analytics/events.json) and the privacy policy's list of events disagreeing;
  - a release build's pack server other than R2 (https://packs.epicaudiogames.com).
Warnings: the optional pieces that are missing (dark and tinted icons, both screenshot sizes, this versionCode's
release notes, What to Test) and wording that may cost a listing (Play's "free", "best" and the like in the title).

Usage (from the repo root): py -3.13 tools/check_store.py [--claims voiceover,talkback]
"""
import argparse
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS_LANE = ROOT / "ios" / "fastlane"
IOS_META = IOS_LANE / "metadata"
WHAT_TO_TEST = IOS_LANE / "testflight" / "what_to_test.txt"
PREVIEWS = IOS_LANE / "app_previews"
PRIVACY_DETAILS = IOS_LANE / "app_privacy_details.json"
PRIVACY_MANIFEST = ROOT / "ios" / "EpicAudioGames" / "Resources" / "PrivacyInfo.xcprivacy"
APP_ICON_SET = ROOT / "ios" / "EpicAudioGames" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BASE_XCCONFIG = ROOT / "ios" / "Config" / "Base.xcconfig"
LOCAL_XCCONFIG = ROOT / "ios" / "Config" / "Local.xcconfig"
PLAY_META = ROOT / "android" / "fastlane" / "metadata" / "android"
ANDROID_FASTFILE = ROOT / "android" / "fastlane" / "Fastfile"
APP_GRADLE = ROOT / "android" / "app" / "build.gradle.kts"
GRADLE_PROPERTIES = ROOT / "android" / "gradle.properties"
CATALOG = ROOT / "games" / "catalog.json"
EVENTS = ROOT / "web" / "analytics" / "events.json"
PRIVACY_PAGE = ROOT / "web" / "public" / "privacy.html"

R2_PACKS_URL = "https://packs.epicaudiogames.com"

# App Store Connect's limits (characters; keywords in bytes), as ios/fastlane/Fastfile has them.
IOS_LIMITS = {"name.txt": 30, "subtitle.txt": 30, "promotional_text.txt": 170, "description.txt": 4000,
              "release_notes.txt": 4000}
IOS_REQUIRED = ("name.txt", "description.txt", "keywords.txt", "support_url.txt", "privacy_url.txt")
IOS_SHARED = ("copyright.txt", "primary_category.txt", "review_information/first_name.txt",
              "review_information/last_name.txt", "review_information/email_address.txt",
              "review_information/phone_number.txt")
NOT_LANGUAGES = ("review_information", "trade_representative_contact_information")
KEYWORDS_BYTES = 100
REVIEW_NOTES_LIMIT = 4000
WHAT_TO_TEST_BYTES = 4000    # fastlane cuts What to Test at 4,000 bytes, and takes out "<"

# The screenshot sizes deliver (fastlane 2.232.2) knows for each iPhone display type, portrait and landscape.
IPHONE_SCREENSHOTS = {
    "APP_IPHONE_67": [(1260, 2736), (1290, 2796), (1320, 2868)],     # the 6.9" and 6.7" iPhones
    "APP_IPHONE_65": [(1242, 2688), (1284, 2778)],
    "APP_IPHONE_61": [(1179, 2556), (1206, 2622)],                   # the 6.3" and 6.1" ("Dynamic Island, medium")
    "APP_IPHONE_58": [(1170, 2532), (1125, 2436), (1080, 2340)],
    "APP_IPHONE_55": [(1242, 2208)],
    "APP_IPHONE_47": [(750, 1334)],
    "APP_IPHONE_40": [(640, 1096), (640, 1136)],
    "APP_IPHONE_35": [(640, 920), (640, 960)],
}
# The App Preview sizes per name token (deliver reads the iPhone from the file name), and Apple's other limits.
PREVIEW_SIZES = {"IPHONE_67": (886, 1920), "IPHONE_65": (886, 1920), "IPHONE_61": (886, 1920),
                 "IPHONE_58": (886, 1920), "IPHONE_55": (1080, 1920), "IPHONE_47": (750, 1334),
                 "IPHONE_40": (1080, 1920)}
PREVIEW_EXTENSIONS = (".mp4", ".mov", ".m4v")
IAP_REVIEW_MIN = (640, 920)

# App Store Connect's App Privacy values (fastlane 2.232.2's Spaceship lists), and PrivacyInfo.xcprivacy's names
# for the ones this app could declare.
APP_PRIVACY_CATEGORIES = {
    "PAYMENT_INFORMATION", "CREDIT_AND_FRAUD", "OTHER_FINANCIAL_INFO", "PRECISE_LOCATION", "SENSITIVE_INFO",
    "PHYSICAL_ADDRESS", "EMAIL_ADDRESS", "NAME", "PHONE_NUMBER", "OTHER_CONTACT_INFO", "CONTACTS",
    "EMAILS_OR_TEXT_MESSAGES", "PHOTOS_OR_VIDEOS", "AUDIO", "GAMEPLAY_CONTENT", "CUSTOMER_SUPPORT",
    "OTHER_USER_CONTENT", "BROWSING_HISTORY", "SEARCH_HISTORY", "USER_ID", "DEVICE_ID", "PURCHASE_HISTORY",
    "PRODUCT_INTERACTION", "ADVERTISING_DATA", "OTHER_USAGE_DATA", "CRASH_DATA", "PERFORMANCE_DATA",
    "OTHER_DIAGNOSTIC_DATA", "OTHER_DATA", "HEALTH", "FITNESS", "COARSE_LOCATION"}
APP_PRIVACY_PURPOSES = {"THIRD_PARTY_ADVERTISING", "DEVELOPERS_ADVERTISING", "ANALYTICS", "PRODUCT_PERSONALIZATION",
                        "APP_FUNCTIONALITY", "OTHER_PURPOSES"}
APP_PRIVACY_PROTECTIONS = {"DATA_USED_TO_TRACK_YOU", "DATA_LINKED_TO_YOU", "DATA_NOT_LINKED_TO_YOU",
                           "DATA_NOT_COLLECTED"}
COLLECTED_DATA_CATEGORIES = {
    "NSPrivacyCollectedDataTypeProductInteraction": "PRODUCT_INTERACTION",
    "NSPrivacyCollectedDataTypeDeviceID": "DEVICE_ID",
    "NSPrivacyCollectedDataTypePurchaseHistory": "PURCHASE_HISTORY",
    "NSPrivacyCollectedDataTypeOtherDiagnosticData": "OTHER_DIAGNOSTIC_DATA",
    "NSPrivacyCollectedDataTypeCrashData": "CRASH_DATA",
    "NSPrivacyCollectedDataTypePerformanceData": "PERFORMANCE_DATA",
    "NSPrivacyCollectedDataTypeOtherUsageData": "OTHER_USAGE_DATA",
    "NSPrivacyCollectedDataTypeUserID": "USER_ID",
    "NSPrivacyCollectedDataTypeEmailAddress": "EMAIL_ADDRESS",
    "NSPrivacyCollectedDataTypeName": "NAME",
    "NSPrivacyCollectedDataTypeAudioData": "AUDIO",
    "NSPrivacyCollectedDataTypeGameplayContent": "GAMEPLAY_CONTENT",
}
COLLECTED_DATA_PURPOSES = {
    "NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising": "THIRD_PARTY_ADVERTISING",
    "NSPrivacyCollectedDataTypePurposeDeveloperAdvertising": "DEVELOPERS_ADVERTISING",
    "NSPrivacyCollectedDataTypePurposeAnalytics": "ANALYTICS",
    "NSPrivacyCollectedDataTypePurposeProductPersonalization": "PRODUCT_PERSONALIZATION",
    "NSPrivacyCollectedDataTypePurposeAppFunctionality": "APP_FUNCTIONALITY",
    "NSPrivacyCollectedDataTypePurposeOther": "OTHER_PURPOSES",
}

# Google Play's limits (characters, as supply sends them).
PLAY_LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
SHORT_DESCRIPTION = 80     # the listing's own rule: all 80 characters, no newline (docs/STORE_LISTING.md)
CHANGELOG_LIMIT = 500
PRODUCT_TITLE_LIMIT = 55
PRODUCT_DESCRIPTION_LIMIT = 200
VIDEO_URL = re.compile(r"https://(www\.)?youtube\.com/watch\?v=[A-Za-z0-9_-]{11}")
# Words Google's metadata policy keeps out of the title and short description (rankings, prices, promotions).
PLAY_PROMO_WORDS = re.compile(r"(?<![\w#])(free|best|#1|top|new|sale|discount|download now|install now)(?!\w)", re.I)

# Platform names App Store metadata can't mention (2.3.10), and claims nobody may make yet.
OTHER_PLATFORMS = re.compile(r"\b(android|talkback|google|wear ?os)\b", re.I)
SCREEN_READERS = {"voiceover": re.compile(r"\bvoice ?over\b", re.I), "talkback": re.compile(r"\btalk ?back\b", re.I)}
RETIRED_CLAIMS = re.compile(r"\b(no tracking|not tracked|data not collected|no data (?:is )?collected|no account"
                            r"|anonymous(?:ly)?)\b", re.I)


class Report:
    """One area's errors and warnings, printed as validate.py prints a game's."""

    def __init__(self, name):
        self.name, self.errors, self.warnings = name, [], []

    def err(self, message):
        self.errors.append(message)

    def warn(self, message):
        self.warnings.append(message)

    def print(self):
        verdict = "OK" if not self.errors else f"{len(self.errors)} error{'s' if len(self.errors) > 1 else ''}"
        print(f"{self.name}: {verdict}")
        for message in self.errors:
            print(f"  x {message}")
        for message in self.warnings:
            print(f"  ! {message}")


def rel(path):
    try:
        return Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def read(path):
    """A text file as git stores it: UTF-8, CRLF read as LF. None if it isn't there."""
    path = Path(path)
    if not path.is_file():
        return None
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


def image_info(path):
    """(width, height, has alpha, colour type) of a PNG, or (width, height, False, None) of a JPEG; None otherwise.

    A PNG has alpha with colour type 4 or 6, or a tRNS chunk (a transparent colour) before its image data."""
    data = Path(path).read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) > 26:
        width, height = struct.unpack(">II", data[16:24])
        colour = data[25]
        alpha = colour in (4, 6)
        pos = 8
        while not alpha and pos + 8 <= len(data):
            length, kind = struct.unpack(">I4s", data[pos:pos + 8])
            if kind == b"IDAT":
                break
            alpha = kind == b"tRNS"
            pos += length + 12
        return width, height, alpha, colour
    if data[:2] == b"\xff\xd8":
        pos = 2
        while pos + 9 <= len(data):
            if data[pos] != 0xFF:
                pos += 1
                continue
            marker = data[pos + 1]
            if marker == 0xFF or marker == 0x01 or 0xD0 <= marker <= 0xD8:
                pos += 1 if marker == 0xFF else 2
                continue
            length = struct.unpack(">H", data[pos + 2:pos + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack(">HH", data[pos + 5:pos + 9])
                return width, height, False, None
            pos += 2 + length
    return None


def images_in(folder, extensions=(".png", ".jpg", ".jpeg")):
    folder = Path(folder)
    return sorted(p for p in folder.glob("*") if p.is_file() and p.suffix.lower() in extensions) if folder.is_dir() else []


def xcconfig_value(path, key):
    """The last assignment of a key in an xcconfig, without its // comment (as ios/fastlane/Fastfile reads it)."""
    text = read(path)
    if text is None:
        return None
    value = None
    for line in text.split("\n"):
        match = re.match(rf"^\s*{re.escape(key)}\s*=\s*(.*)$", line)
        if match:
            value = re.sub(r"\s*//.*$", "", match.group(1)).strip()
    return value


def gradle_property(path, key):
    """A .properties value as Java reads it: the last key=value, key: value or key value line, escapes undone."""
    text = read(path)
    if text is None:
        return None
    value = None
    for line in text.split("\n"):
        match = re.match(rf"^\s*{re.escape(key)}(?:\s*[=:]\s*|\s+)(.*)$", line)
        if match:
            value = re.sub(r"\\(.)", r"\1", match.group(1))
    return value


def gradle_value(name):
    """versionCode or versionName in android/app/build.gradle.kts."""
    match = re.search(rf"^\s*{re.escape(name)}\s*=\s*\"?([^\"\s]+)\"?", read(APP_GRADLE) or "", re.M)
    return match.group(1) if match else None


def catalog_products():
    games = json.loads(read(CATALOG))["games"]
    return [pack["product"] for game in games for pack in game.get("packs", [])]


def public_ios_texts():
    """The App Store's public texts: each language's listing (not the URLs or App Review's notes)."""
    names = ("name.txt", "subtitle.txt", "description.txt", "keywords.txt", "promotional_text.txt",
             "release_notes.txt")
    return [d / n for d in ios_languages() for n in names if (d / n).is_file()]


def ios_languages():
    if not IOS_META.is_dir():
        return []
    return sorted(d for d in IOS_META.iterdir() if d.is_dir() and d.name not in NOT_LANGUAGES)


def play_languages():
    return sorted(d for d in PLAY_META.iterdir() if d.is_dir()) if PLAY_META.is_dir() else []


def public_play_texts():
    texts = []
    for d in play_languages():
        texts += [d / n for n in ("title.txt", "short_description.txt", "full_description.txt") if (d / n).is_file()]
        texts += sorted((d / "changelogs").glob("*.txt"))
    return texts


# ---------------------------------------------------------------------------------------------------------------------
# The App Store

def check_ios_listing(r):
    languages = ios_languages()
    if not any(d.name == "en-US" for d in languages):
        r.err(f"{rel(IOS_META)}/en-US/ is missing: en-US is the app's primary language")
    for d in languages:
        for name in IOS_REQUIRED:
            if not (read(d / name) or "").strip():
                r.err(f"{rel(d / name)} is missing or empty")
        for name, limit in IOS_LIMITS.items():
            text = (read(d / name) or "").strip()      # deliver strips each text
            if len(text) > limit:
                r.err(f"{rel(d / name)} is {len(text)} characters; the limit is {limit}")
        for name in ("support_url.txt", "privacy_url.txt", "marketing_url.txt"):
            url = (read(d / name) or "").strip()
            if url and not url.startswith("https://"):
                r.err(f"{rel(d / name)} isn't an https:// address: {url}")
        check_keywords(r, d)
    for name in IOS_SHARED:
        if not (read(IOS_META / name) or "").strip():
            r.err(f"{rel(IOS_META / name)} is missing or empty")
    notes = (read(IOS_META / "review_information" / "notes.txt") or "").strip()
    if len(notes) > REVIEW_NOTES_LIMIT:
        r.err(f"{rel(IOS_META / 'review_information' / 'notes.txt')} is {len(notes)} characters; "
              f"the limit is {REVIEW_NOTES_LIMIT}")

    what = (read(WHAT_TO_TEST) or "").strip()
    if not what:
        r.warn(f"{rel(WHAT_TO_TEST)} is missing or empty: TestFlight builds go up without What to Test")
    else:
        if len(what.encode()) > WHAT_TO_TEST_BYTES:
            r.err(f"{rel(WHAT_TO_TEST)} is {len(what.encode())} bytes; TestFlight takes {WHAT_TO_TEST_BYTES}")
        if "<" in what:
            r.warn(f'{rel(WHAT_TO_TEST)} has a "<", which fastlane takes out')


def check_keywords(r, language_dir):
    path = language_dir / "keywords.txt"
    text = (read(path) or "").strip()
    if not text:
        return
    size = len(text.encode())
    if size > KEYWORDS_BYTES:
        r.err(f"{rel(path)} is {size} bytes; Apple takes {KEYWORDS_BYTES}")
    words = [w.strip().lower() for w in text.split(",")]
    if any(w != raw for w, raw in zip(words, text.lower().split(","))):
        r.warn(f"{rel(path)}: spaces around the commas count towards the {KEYWORDS_BYTES} bytes")
    if len(set(words)) < len(words):
        r.warn(f"{rel(path)}: a keyword is there twice")
    indexed = set(re.findall(r"[a-z]+", " ".join((read(language_dir / n) or "").lower()
                                                  for n in ("name.txt", "subtitle.txt"))))
    already = sorted({w for w in words for part in w.split() if part in indexed})
    if already:
        r.warn(f"{rel(path)}: {', '.join(already)} repeat words of the name or subtitle, which Apple indexes anyway")


def check_wording(r, claims):
    """Other platforms in App Store text; claims the apps can't make yet, in either store."""
    ios_files = sorted(p for p in IOS_META.rglob("*.txt")) + ([WHAT_TO_TEST] if WHAT_TO_TEST.is_file() else [])
    for path in ios_files:
        for match in sorted({m.group(0) for m in OTHER_PLATFORMS.finditer(read(path) or "")}):
            r.err(f'{rel(path)} says "{match}": App Store metadata can\'t name other platforms (2.3.10)')
    for path in public_ios_texts() + public_play_texts():
        text = read(path) or ""
        for reader, pattern in SCREEN_READERS.items():
            if reader not in claims and pattern.search(text):
                r.err(f"{rel(path)} mentions {pattern.search(text).group(0)}: not before the real-device test "
                      f"(docs/DESIGN.md; then --claims {reader})")
    for path in public_ios_texts() + public_play_texts() + ([WHAT_TO_TEST] if WHAT_TO_TEST.is_file() else []):
        for match in sorted({m.group(0) for m in RETIRED_CLAIMS.finditer(read(path) or "")}):
            r.err(f'{rel(path)} says "{match}": untrue now the apps share usage data (docs/STORE_LISTING.md)')


def check_ios_images(r):
    # The icon: 1024 x 1024 without alpha, and iOS 18's dark and tinted ones.
    contents = read(APP_ICON_SET / "Contents.json")
    if contents is None:
        r.err(f"{rel(APP_ICON_SET / 'Contents.json')} is missing (the app icon)")
    else:
        images = json.loads(contents).get("images", [])

        def look(image):
            return next((a.get("value") for a in image.get("appearances", []) if a.get("appearance") == "luminosity"),
                        None)
        main = next((i for i in images if i.get("filename") and look(i) is None), None)
        if main is None:
            r.err(f"{rel(APP_ICON_SET / 'Contents.json')} names no icon file")
        elif not (APP_ICON_SET / main["filename"]).is_file():
            r.err(f"{rel(APP_ICON_SET / main['filename'])} is missing (the app icon)")
        else:
            info = image_info(APP_ICON_SET / main["filename"])
            if not info or info[:2] != (1024, 1024):
                r.err(f"{rel(APP_ICON_SET / main['filename'])} should be a 1024 x 1024 PNG")
            if info and info[2]:
                r.err(f"{rel(APP_ICON_SET / main['filename'])} has an alpha channel: App Store Connect refuses the "
                      f"build (ITMS-90717)")
        for appearance in ("dark", "tinted"):
            if not any(i.get("filename") and look(i) == appearance for i in images):
                r.warn(f"{rel(APP_ICON_SET)} has no {appearance} icon for iOS 18's {appearance} home screen "
                       f"(tools/make_art.py export icons makes one)")

    # The screenshots: sizes deliver knows, at least one of the big iPhones, both 6.9" and 6.3", no alpha.
    shots_dir = IOS_LANE / "screenshots"
    languages = sorted(d for d in shots_dir.iterdir() if d.is_dir()) if shots_dir.is_dir() else []
    if not any(images_in(d) for d in languages):
        r.warn(f"no screenshots in {rel(shots_dir)}/en-US/ yet")
    for d in languages:
        by_type = {}
        for path in images_in(d):
            info = image_info(path)
            if info is None:
                r.err(f"{rel(path)} isn't a PNG or JPEG image")
                continue
            size = tuple(sorted(info[:2]))
            kind = next((t for t, sizes in IPHONE_SCREENSHOTS.items() if size in sizes), None)
            if kind is None:
                r.err(f"{rel(path)} is {info[0]} x {info[1]}: not a size deliver knows for an iPhone")
            else:
                by_type.setdefault(kind, []).append(path)
            if info[2]:
                r.err(f"{rel(path)} has an alpha channel; App Store screenshots can't")
        if by_type and not set(by_type) & {"APP_IPHONE_67", "APP_IPHONE_65", "APP_IPHONE_61"}:
            r.err(f"{rel(d)}: an iPhone app needs 6.9-inch (1320 x 2868), 6.5-inch (1284 x 2778) or 6.3-inch "
                  f"(1206 x 2622) screenshots")
        elif by_type and not {"APP_IPHONE_67", "APP_IPHONE_61"} <= set(by_type):
            r.warn(f"{rel(d)}: not both the 6.9-inch (1320 x 2868) and 6.3-inch (1206 x 2622) sets "
                   f"(tools/make_art.py shots ios --sizes 6.9,6.3 makes both)")
        for kind, paths in by_type.items():
            if len(paths) > 10:
                r.err(f"{rel(d)}: {len(paths)} {kind} screenshots; at most 10")

    # Each in-app purchase's screenshot for App Review.
    for product in catalog_products():
        path = next((IOS_LANE / "iap_review" / f"{product}.{ext}" for ext in ("png", "jpg", "jpeg")
                     if (IOS_LANE / "iap_review" / f"{product}.{ext}").is_file()), None)
        if path is None:
            r.warn(f"{rel(IOS_LANE / 'iap_review')}/{product}.png is missing (the in-app purchase's screenshot for "
                   f"App Review)")
            continue
        info = image_info(path)
        if info is None:
            r.err(f"{rel(path)} isn't a PNG or JPEG image")
        elif min(info[:2]) < min(IAP_REVIEW_MIN) or max(info[:2]) < max(IAP_REVIEW_MIN):
            r.err(f"{rel(path)} is {info[0]} x {info[1]}; Apple wants at least 640 x 920")


def check_previews(r):
    videos = sorted(p for p in PREVIEWS.glob("*/*") if p.suffix.lower() in PREVIEW_EXTENSIONS) \
        if PREVIEWS.is_dir() else []
    if not videos:
        return
    counts = {}
    for path in videos:
        token = next((t for t in PREVIEW_SIZES if t in path.name.upper()), None)
        if token is None:
            r.err(f"{rel(path)}: the name doesn't say the iPhone size ({', '.join(PREVIEW_SIZES)}), so deliver "
                  f"skips it")
            continue
        counts[(path.parent.name, token)] = counts.get((path.parent.name, token), 0) + 1
        if path.stat().st_size > 500 * 1024 * 1024:
            r.err(f"{rel(path)} is over 500 MB")
        try:
            out = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams",
                                  str(path)], capture_output=True, text=True)
        except FileNotFoundError:
            r.warn("ffprobe isn't installed: the App Previews' codecs, sizes and lengths weren't checked")
            return
        if out.returncode != 0:
            r.err(f"{rel(path)}: ffprobe can't read it")
            continue
        info = json.loads(out.stdout)
        streams = info.get("streams", [])
        video = next((s for s in streams if s.get("codec_type") == "video"), None)
        audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
        seconds = float(info.get("format", {}).get("duration", 0) or 0)
        if video is None:
            r.err(f"{rel(path)} has no video")
        else:
            width, height = video.get("width"), video.get("height")
            if tuple(sorted((width, height))) != tuple(sorted(PREVIEW_SIZES[token])):
                r.err(f"{rel(path)} is {width} x {height}; for {token} Apple takes "
                      f"{PREVIEW_SIZES[token][0]} x {PREVIEW_SIZES[token][1]} (or turned)")
            if video.get("codec_name") != "h264":
                r.err(f"{rel(path)}: the video is {video.get('codec_name')}, not H.264")
            elif video.get("profile") != "High":
                r.err(f"{rel(path)}: H.264 {video.get('profile')} profile, not High")
            if int(video.get("level") or 0) > 40:
                r.err(f"{rel(path)}: H.264 level {int(video['level']) / 10}, above 4.0")
            if video.get("pix_fmt") != "yuv420p":
                r.err(f"{rel(path)}: pixels are {video.get('pix_fmt')}, not yuv420p")
            num, _, den = (video.get("avg_frame_rate") or "0/0").partition("/")
            fps = float(num) / float(den) if den and float(den) else 0
            if fps > 30.01:
                r.err(f"{rel(path)}: {fps:.2f} frames a second; Apple takes 30 at most")
            if audio and abs(float(video.get("duration") or seconds) - float(audio.get("duration") or seconds)) > 0.1:
                r.warn(f"{rel(path)}: the video and the sound differ in length by more than 0.1 s")
        if audio is None:
            r.err(f"{rel(path)} has no sound track (Apple wants stereo AAC)")
        else:
            if audio.get("codec_name") != "aac":
                r.err(f"{rel(path)}: the sound is {audio.get('codec_name')}, not AAC")
            if int(audio.get("channels") or 0) != 2:
                r.err(f"{rel(path)}: the sound isn't stereo ({audio.get('channels')} channel(s))")
            if str(audio.get("sample_rate")) not in ("44100", "48000"):
                r.err(f"{rel(path)}: the sound is {audio.get('sample_rate')} Hz, not 44,100 or 48,000")
        if not 15 <= seconds <= 30:
            r.err(f"{rel(path)} is {seconds:.1f} seconds; Apple takes 15 to 30")
    for (language, token), count in counts.items():
        if count > 3:
            r.err(f"{rel(PREVIEWS)}/{language}: {count} {token} previews; Apple takes 3")


def check_ios_privacy(r):
    """app_privacy_details.json's values, and that it says what PrivacyInfo.xcprivacy says."""
    text = read(PRIVACY_DETAILS)
    if text is None:
        r.err(f"{rel(PRIVACY_DETAILS)} is missing (the App Privacy answers)")
        return
    usages = json.loads(text)
    if not isinstance(usages, list) or not usages:
        r.err(f"{rel(PRIVACY_DETAILS)} should be a list of data uses (or one DATA_NOT_COLLECTED entry)")
        return
    answered = {}
    for index, usage in enumerate(usages, 1):
        where = f"{rel(PRIVACY_DETAILS)} entry {index}"
        protections = usage.get("data_protections") or []
        if not protections:
            r.err(f"{where}: needs data_protections")
            continue
        if "DATA_NOT_COLLECTED" in protections:
            if len(usages) > 1:
                r.err(f"{where}: DATA_NOT_COLLECTED has to be the only entry")
            continue
        if usage.get("category") not in APP_PRIVACY_CATEGORIES:
            r.err(f"{where}: unknown category {usage.get('category')!r}")
        if not usage.get("purposes"):
            r.err(f"{where}: needs purposes")
        for purpose in usage.get("purposes") or []:
            if purpose not in APP_PRIVACY_PURPOSES:
                r.err(f"{where}: unknown purpose {purpose}")
        for protection in protections:
            if protection not in APP_PRIVACY_PROTECTIONS:
                r.err(f"{where}: unknown data protection {protection}")
        answered[usage.get("category")] = (sorted(usage.get("purposes") or []), "DATA_LINKED_TO_YOU" in protections,
                                           "DATA_USED_TO_TRACK_YOU" in protections)

    if not PRIVACY_MANIFEST.is_file():
        r.err(f"{rel(PRIVACY_MANIFEST)} is missing (the app's privacy manifest)")
        return
    manifest = plistlib.loads(PRIVACY_MANIFEST.read_bytes())
    declared = {}
    for entry in manifest.get("NSPrivacyCollectedDataTypes", []):
        kind = entry.get("NSPrivacyCollectedDataType")
        category = COLLECTED_DATA_CATEGORIES.get(kind)
        if category is None:
            r.warn(f"{rel(PRIVACY_MANIFEST)}: {kind} isn't in COLLECTED_DATA_CATEGORIES (here and in the Fastfile), "
                   f"so it wasn't compared")
            continue
        purposes = sorted(COLLECTED_DATA_PURPOSES.get(p, p) for p in entry.get("NSPrivacyCollectedDataTypePurposes", []))
        declared[category] = (purposes, entry.get("NSPrivacyCollectedDataTypeLinked") is True,
                              entry.get("NSPrivacyCollectedDataTypeTracking") is True)
    if manifest.get("NSPrivacyTracking") is not True and any(t for _, _, t in declared.values()):
        r.err(f"{rel(PRIVACY_MANIFEST)}: NSPrivacyTracking is false, but a collected data type is used for tracking")
    where = f"{rel(PRIVACY_MANIFEST)} and {rel(PRIVACY_DETAILS)}"
    for category in sorted(set(declared) - set(answered)):
        r.err(f"{where}: the manifest collects {category}, the App Privacy answers don't")
    for category in sorted(set(answered) - set(declared)):
        r.err(f"{where}: the App Privacy answers collect {category}, the manifest doesn't")
    for category in sorted(set(declared) & set(answered)):
        (ours_p, ours_l, ours_t), (theirs_p, theirs_l, theirs_t) = declared[category], answered[category]
        if ours_p != theirs_p:
            r.err(f"{where}: {category}'s purposes differ (the manifest: {', '.join(ours_p)}; the answers: "
                  f"{', '.join(theirs_p)})")
        if ours_l != theirs_l:
            r.err(f"{where}: {category} is linked to the player in one and not the other")
        if ours_t != theirs_t:
            r.err(f"{where}: {category} is used for tracking in one and not the other")


# ---------------------------------------------------------------------------------------------------------------------
# Google Play

def check_play_listing(r):
    languages = play_languages()
    if not any(d.name == "en-US" for d in languages):
        r.err(f"{rel(PLAY_META)}/en-US/ is missing: en-US is the listing's default language")
    version_code = gradle_value("versionCode")
    for d in languages:
        for name, limit in PLAY_LIMITS.items():
            text = read(d / name)
            if not (text or "").strip():
                r.err(f"{rel(d / name)} is missing or empty")
            elif len(text) > limit:
                r.err(f"{rel(d / name)} is {len(text)} characters as supply sends it (a newline at the end counts); "
                      f"the limit is {limit}")
        short = read(d / "short_description.txt") or ""
        if short and short != short.strip():
            r.err(f"{rel(d / 'short_description.txt')} has a newline or spaces at an end, and supply sends them")
        elif short and len(short) < SHORT_DESCRIPTION:
            r.err(f"{rel(d / 'short_description.txt')} is {len(short)} characters; the listing uses all "
                  f"{SHORT_DESCRIPTION} (docs/STORE_LISTING.md)")
        for name in ("title.txt", "short_description.txt"):
            for match in sorted({m.group(0) for m in PLAY_PROMO_WORDS.finditer(read(d / name) or "")}):
                r.warn(f'{rel(d / name)} says "{match}": Google keeps prices, rankings and promotions out of it')
        for path in sorted((d / "changelogs").glob("*.txt")):
            text = read(path)
            if len(text) > CHANGELOG_LIMIT:
                r.err(f"{rel(path)} is {len(text)} characters as supply sends it; the limit is {CHANGELOG_LIMIT}")
        if version_code and not (d / "changelogs" / f"{version_code}.txt").is_file():
            fallback = "changelogs/default.txt" if (d / "changelogs" / "default.txt").is_file() else "no release notes"
            r.warn(f"{rel(d / 'changelogs' / f'{version_code}.txt')} is missing (versionCode {version_code}): the "
                   f"internal lane sends {fallback} instead")
        video = read(d / "video.txt")
        if video is not None:
            if not video.strip():
                r.warn(f"{rel(d / 'video.txt')} is empty: supply would take the listing's video away")
            elif video != video.strip():
                r.err(f"{rel(d / 'video.txt')} has a newline or spaces around the address, and supply sends them")
            elif not VIDEO_URL.fullmatch(video):
                r.err(f"{rel(d / 'video.txt')} isn't a YouTube video's address "
                      f"(https://www.youtube.com/watch?v=<id>): {video}")
        check_play_images(r, d / "images", required=d.name == "en-US")


def check_play_images(r, folder, required):
    icon = folder / "icon.png"
    if icon.is_file():
        info = image_info(icon)
        if not info or info[:2] != (512, 512):
            r.err(f"{rel(icon)} should be 512 x 512")
        if icon.stat().st_size > 1024 * 1024:
            r.err(f"{rel(icon)} is over 1 MB")
        if not info or info[3] != 6:
            r.err(f"{rel(icon)} should be a 32-bit PNG, with alpha (Google's spec)")
    elif required:
        r.err(f"{rel(icon)} is missing (512 x 512 PNG)")

    feature = next((folder / f"featureGraphic.{e}" for e in ("png", "jpg", "jpeg")
                    if (folder / f"featureGraphic.{e}").is_file()), None)
    if feature:
        info = image_info(feature)
        if not info or info[:2] != (1024, 500):
            r.err(f"{rel(feature)} should be 1024 x 500")
        if feature.stat().st_size > 15 * 1024 * 1024:
            r.err(f"{rel(feature)} is over 15 MB")
        if info and info[2]:
            r.err(f"{rel(feature)} has an alpha channel; Google wants it without")
    elif required:
        r.err(f"{rel(folder / 'featureGraphic.png')} is missing (1024 x 500 PNG or JPEG)")

    shots = images_in(folder / "phoneScreenshots")
    if not shots:
        if required:
            r.warn(f"no phone screenshots in {rel(folder / 'phoneScreenshots')}/ yet (2 to 8)")
    elif not 2 <= len(shots) <= 8:
        r.err(f"{rel(folder / 'phoneScreenshots')}/ has {len(shots)} screenshots; Google takes 2 to 8")
    for path in shots:
        info = image_info(path)
        if info is None:
            r.err(f"{rel(path)} isn't a PNG or JPEG image")
            continue
        width, height = info[:2]
        if min(width, height) < 320 or max(width, height) > 3840 or max(width, height) > 2 * min(width, height):
            r.err(f"{rel(path)} is {width} x {height}: each side 320 to 3840, the long side at most twice the short")
        elif height * 9 != width * 16 or width < 1080:
            r.warn(f"{rel(path)} is {width} x {height}, not 9:16 portrait of at least 1080 x 1920: it won't count "
                   f"towards Google Play's promotion of games")
        if path.stat().st_size > 8 * 1024 * 1024:
            r.err(f"{rel(path)} is over 8 MB")
        if info[2]:
            r.err(f"{rel(path)} has an alpha channel; Google wants screenshots without")


def ruby_strings(source):
    """The double-quoted Ruby string literals in a piece of source, joined (Ruby joins adjacent literals)."""
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', source)
    return "".join(re.sub(r"\\(.)", r"\1", p) for p in parts)


def check_play_products(r):
    """PLAY_PRODUCTS in android/fastlane/Fastfile against games/catalog.json and Google's limits."""
    text = read(ANDROID_FASTFILE) or ""
    block = re.search(r"^PLAY_PRODUCTS = \{\n(.*?)^\}\.freeze", text, re.S | re.M)
    if not block:
        r.err(f"{rel(ANDROID_FASTFILE)}: no PLAY_PRODUCTS")
        return
    products = {}
    for match in re.finditer(r'"(\w+)" => \{\s*title:(.*?),\s*description:(.*?)\n\s*\}', block.group(1), re.S):
        products[match.group(1)] = (ruby_strings(match.group(2)), ruby_strings(match.group(3)).strip())
    ids = catalog_products()
    for product in ids:
        if product not in products:
            r.err(f"{product} is a pack in games/catalog.json but has no Play name: add it to PLAY_PRODUCTS")
    for product in products:
        if product not in ids:
            r.err(f"PLAY_PRODUCTS has {product}, which games/catalog.json doesn't sell")
    for product, (title, description) in products.items():
        if not title or len(title) > PRODUCT_TITLE_LIMIT:
            r.err(f"{product}: the name is {len(title)} characters; Google takes 1 to {PRODUCT_TITLE_LIMIT}")
        if not description or len(description) > PRODUCT_DESCRIPTION_LIMIT:
            r.err(f"{product}: the description is {len(description)} characters; Google takes 1 to "
                  f"{PRODUCT_DESCRIPTION_LIMIT}")


# ---------------------------------------------------------------------------------------------------------------------
# Both apps

def check_usage_data(r):
    """Every event in the whitelist is in the privacy policy's list (<li data-event="...">), and nothing else is."""
    events_text = read(EVENTS)
    if events_text is None:
        r.warn(f"{rel(EVENTS)} isn't there yet: the privacy policy's list of events wasn't checked")
        return
    events = set(json.loads(events_text).get("events", {}))
    page = read(PRIVACY_PAGE) or ""
    listed = set(re.findall(r"<li\b[^>]*\bdata-event=\"([^\"]+)\"", page))
    if 'id="usage-data"' not in page:
        r.err(f'{rel(PRIVACY_PAGE)} has no id="usage-data" section (App Store Connect\'s Privacy Choices URL '
              f'points at it)')
    for name in sorted(events - listed):
        r.err(f'{rel(PRIVACY_PAGE)} doesn\'t list {name} (no <li data-event="{name}">), which the apps send')
    for name in sorted(listed - events):
        r.err(f"{rel(PRIVACY_PAGE)} lists {name}, which isn't in {rel(EVENTS)}")


def pack_urls():
    """The pack server each app's release build gets, as Xcode and Gradle pick it: [(app, url or "", where)].

    iPhone: Local.xcconfig's EPIC_PACKS_URL if it sets one, else Base.xcconfig's (the $() keeps // from starting a
    comment). Android: Gradle's order for the epicPacksUrl property: the environment (ORG_GRADLE_PROJECT_epicPacksUrl),
    then the user's gradle.properties (GRADLE_USER_HOME, else ~/.gradle), then android/gradle.properties."""
    source = LOCAL_XCCONFIG if xcconfig_value(LOCAL_XCCONFIG, "EPIC_PACKS_URL") is not None else BASE_XCCONFIG
    urls = [("iPhone", (xcconfig_value(source, "EPIC_PACKS_URL") or "").replace("$()", ""), rel(source))]

    user_home = Path(os.environ["GRADLE_USER_HOME"]) if os.environ.get("GRADLE_USER_HOME") else Path.home() / ".gradle"
    if "ORG_GRADLE_PROJECT_epicPacksUrl" in os.environ:
        urls.append(("Android", os.environ["ORG_GRADLE_PROJECT_epicPacksUrl"], "ORG_GRADLE_PROJECT_epicPacksUrl"))
    else:
        found = ("", "nothing sets epicPacksUrl")
        for path in (user_home / "gradle.properties", GRADLE_PROPERTIES):
            value = gradle_property(path, "epicPacksUrl")
            if value is not None:
                found = (value, rel(path))
                break
        urls.append(("Android", *found))
    return urls


def check_packs_url(r):
    """Both apps' release builds have to download packs from R2."""
    for app, url, where in pack_urls():
        if not url:
            r.warn(f"{app}: no pack server ({where}), so release builds would hide buying packs")
        elif url != R2_PACKS_URL:
            r.err(f"{app}: the release builds' pack server is {url} ({where}), not {R2_PACKS_URL}"
                  + (": take EPIC_PACKS_URL out of ios/Config/Local.xcconfig" if app == "iPhone" else ""))


def check_versions(r):
    ios = xcconfig_value(BASE_XCCONFIG, "MARKETING_VERSION")
    android = gradle_value("versionName")
    if ios and android and ios != android:
        r.warn(f"versionName is {android} (android/app/build.gradle.kts) but the iPhone app is {ios}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--claims", default="", help="screen readers the listings may name after the real-device test: "
                                                  "voiceover, talkback, or both (comma-separated)")
    args = ap.parse_args()
    claims = {c.strip().lower() for c in args.claims.split(",") if c.strip()}
    unknown = claims - set(SCREEN_READERS)
    if unknown:
        ap.error(f"--claims takes voiceover and talkback, not {', '.join(sorted(unknown))}")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    areas = [
        ("App Store listing", check_ios_listing),
        ("App Store images", check_ios_images),
        ("App Store previews", check_previews),
        ("App Privacy", check_ios_privacy),
        ("Google Play listing", check_play_listing),
        ("Google Play products", check_play_products),
        ("Wording", lambda r: check_wording(r, claims)),
        ("Usage data", check_usage_data),
        ("Pack server", check_packs_url),
        ("Versions", check_versions),
    ]
    failed = False
    for name, check in areas:
        report = Report(name)
        try:
            check(report)
        except (ValueError, KeyError, TypeError, AttributeError, OSError) as e:   # a file that doesn't parse
            report.err(f"couldn't check: {type(e).__name__}: {e}")
        report.print()
        failed = failed or bool(report.errors)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
