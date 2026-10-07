#!/bin/bash
set -euo pipefail

# Build and launch a separate app identity so preview preferences stay isolated.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${BORING_NOTCH_DERIVED_DATA:-$PROJECT_ROOT/build/DerivedData}"
PREVIEW_APP="$PROJECT_ROOT/build/Calendar Preview.app"
PREVIEW_ID=dev.hadg.boringnotch.calendar-preview

cd "$PROJECT_ROOT"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

# ditto updates an existing preview without altering the built app.
ditto "$DERIVED_DATA/Build/Products/Debug/Boring Notch.app" "$PREVIEW_APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.hadg.boringnotch.calendar-preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Calendar Preview' "$PREVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Calendar Preview' "$PREVIEW_APP/Contents/Info.plist"
# Sign the helper independently, then the app with its real sandbox entitlements.
# This keeps the usage reader's XPC boundary representative of a distributed app.
codesign --force --deep --sign - "$PREVIEW_APP"
codesign --force --sign - --entitlements "$PROJECT_ROOT/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" \
  "$PREVIEW_APP/Contents/XPCServices/BoringNotchXPCHelper.xpc"
PREVIEW_ENTITLEMENTS="$(mktemp /private/tmp/notch-preview-entitlements.XXXXXX)"
trap 'rm -f "$PREVIEW_ENTITLEMENTS"' EXIT
cp "$PROJECT_ROOT/boringNotch/boringNotch.entitlements" "$PREVIEW_ENTITLEMENTS"
for MACH_INDEX in 0 1; do
  MACH_SUFFIX=spks
  [[ "$MACH_INDEX" == 1 ]] && MACH_SUFFIX=spki
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.temporary-exception.mach-lookup.global-name:$MACH_INDEX $PREVIEW_ID-$MACH_SUFFIX" "$PREVIEW_ENTITLEMENTS"
done
codesign --force --sign - --entitlements "$PREVIEW_ENTITLEMENTS" "$PREVIEW_APP"

defaults write "$PREVIEW_ID" firstLaunch -bool false
defaults write "$PREVIEW_ID" showCalendar -bool true
defaults write "$PREVIEW_ID" hudReplacement -bool false
defaults write "$PREVIEW_ID" expandedDragDetection -bool false
defaults write "$PREVIEW_ID" SUEnableAutomaticChecks -bool false
if [[ -n "${BORING_NOTCH_CODEX_PREVIEW:-}" ]]; then
  open -n "$PREVIEW_APP" --args --codex-preview "$BORING_NOTCH_CODEX_PREVIEW"
else
  open -n "$PREVIEW_APP"
fi

printf '\nPreview launched. Hover over the notch, then click its month header.\n'
printf 'Quit any other running notch app if its window overlaps the preview.\n'
