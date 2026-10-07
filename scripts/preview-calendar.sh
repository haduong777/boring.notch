#!/bin/bash
set -euo pipefail

# Build and launch a separate app identity so preview preferences stay isolated.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${BORING_NOTCH_DERIVED_DATA:-$PROJECT_ROOT/build/DerivedData}"
PREVIEW_APP="$PROJECT_ROOT/build/Calendar Preview.app"

cd "$PROJECT_ROOT"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

# ditto updates an existing preview without altering the built app.
ditto "$DERIVED_DATA/Build/Products/Debug/Boring Notch.app" "$PREVIEW_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hadg.boringnotch.calendar-preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Calendar Preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Calendar Preview' "$PREVIEW_APP/Contents/Info.plist"
codesign --force --deep --sign - "$PREVIEW_APP"

PREVIEW_ID=dev.hadg.boringnotch.calendar-preview
defaults write "$PREVIEW_ID" firstLaunch -bool false
defaults write "$PREVIEW_ID" showCalendar -bool true
defaults write "$PREVIEW_ID" hudReplacement -bool false
defaults write "$PREVIEW_ID" expandedDragDetection -bool false
defaults write "$PREVIEW_ID" SUEnableAutomaticChecks -bool false
open -n "$PREVIEW_APP"

printf '\nPreview launched. Hover over the notch, then click its month header.\n'
printf 'Quit any other running notch app if its window overlaps the preview.\n'
