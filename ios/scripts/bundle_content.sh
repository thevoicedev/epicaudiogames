#!/bin/bash
# Puts the games in the app, as android/app/build.gradle.kts puts them in the APK's assets:
#   games/    -> <app>/Games/    catalog.json, each game's map.json and Nuclear War's clips.json; not packs/ (they
#                                come in their own downloads) or lines.json (what Nuclear War's clips were made from);
#   content/  -> <app>/Content/  each game's audio and cover, built by tools/;
#   the Lilita One font (android/app/src/main/res/font) -> <app>/Fonts/.
# Run by the app target's "Bundle game content" build phase, every build (rsync copies only what changed).
#
# EPIC_CONTENT_DIR    the content folder, if not content/ at the repo root (e.g. build/placeholder-content, made by
#                     ios/scripts/placeholder_content.py). A build setting or an environment variable.
# EPIC_CONTENT_GAMES  Debug only: the game ids whose content to bundle, space-separated (a quicker build).
# Without content, a Debug build warns and has no audio; a Release build fails (EPIC_CONTENT_REQUIRED).
set -euo pipefail

: "${SRCROOT:?run this from the Xcode build phase}"
: "${TARGET_BUILD_DIR:?}" "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
REPO="$(cd "$SRCROOT/.." && pwd)"
DST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
CONTENT="${EPIC_CONTENT_DIR:-$REPO/content}"
case "$CONTENT" in /*) ;; *) CONTENT="$REPO/$CONTENT" ;; esac      # a relative path is from the repo root
CONTENT="${CONTENT%/}"
FONT="$REPO/android/app/src/main/res/font/lilita_one.ttf"

# Android's ignoreAssetsPatterns ("<dir>packs", "<file>lines.json"), plus hidden files and unfinished downloads.
SKIP=(--exclude 'packs/' --exclude 'lines.json' --exclude '.*' --exclude '*.part' --exclude '*.tmp.*')

mkdir -p "$DST/Games" "$DST/Fonts"
rsync -a --delete "${SKIP[@]}" "$REPO/games/" "$DST/Games/"
cp -p "$FONT" "$DST/Fonts/lilita_one.ttf"

if [ -d "$CONTENT" ] && [ -n "$(ls -A "$CONTENT")" ]; then
    ONLY=()
    if [ "${CONFIGURATION:-}" = "Debug" ] && [ -n "${EPIC_CONTENT_GAMES:-}" ]; then
        for id in $EPIC_CONTENT_GAMES; do
            ONLY+=(--include "/$id/***")
        done
        ONLY+=(--exclude '/*' --delete-excluded)
        echo "warning: bundling the content of $EPIC_CONTENT_GAMES only (EPIC_CONTENT_GAMES)"
    fi
    mkdir -p "$DST/Content"
    rsync -a --delete "${SKIP[@]}" ${ONLY[@]+"${ONLY[@]}"} "$CONTENT/" "$DST/Content/"
    echo "Bundled $(find "$DST/Content" -type f | wc -l | tr -d ' ') content files from $CONTENT"
else
    rm -rf "$DST/Content"
    if [ "${EPIC_CONTENT_REQUIRED:-NO}" = "YES" ]; then
        echo "error: no game content in $CONTENT. Copy the built content/ there, or set EPIC_CONTENT_DIR."
        exit 1
    fi
    echo "warning: no game content in $CONTENT, so the games have no audio or covers. Set EPIC_CONTENT_DIR (e.g. to build/placeholder-content, made by ios/scripts/placeholder_content.py)."
fi
