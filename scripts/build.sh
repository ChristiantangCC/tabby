#!/bin/bash
# Builds Tabby.app into ./build and signs it. A real signing identity keeps the
# Accessibility / Screen Recording grants across rebuilds; ad-hoc resets them.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Tabby.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tabby "$APP/Contents/MacOS/Tabby"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
if [ -n "$SIGN_ID" ] && codesign --force --sign "$SIGN_ID" "$APP"; then
  echo "Built $APP (signed with: $SIGN_ID)"
else
  codesign --force --sign - "$APP"
  echo "Built $APP (ad-hoc signed: permissions must be re-granted after each rebuild)"
fi

# Install so it's easy to find in System Settings and works with "Launch at login".
if [ "${INSTALL:-1}" = "1" ]; then
  pkill -x Tabby || true
  rm -rf /Applications/Tabby.app
  ditto "$APP" /Applications/Tabby.app
  echo "Installed to /Applications/Tabby.app"
fi
