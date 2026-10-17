#!/bin/bash
# Builds Tabby.app into ./build and signs it. A real signing identity keeps the
# Accessibility / Screen Recording grants across rebuilds; ad-hoc resets them.
set -euo pipefail
cd "$(dirname "$0")/.."

# ARCHS="arm64 x86_64" builds one universal binary (used for releases).
# Each architecture is built on its own and merged with lipo, which works with
# just the command line tools (SwiftPM's --arch needs full Xcode).
if [ -n "${ARCHS:-}" ]; then
  SLICES=()
  for arch in $ARCHS; do
    swift build -c release --triple "$arch-apple-macosx14.0"
    SLICES+=(".build/$arch-apple-macosx/release/Tabby")
  done
  mkdir -p .build/universal
  lipo -create "${SLICES[@]}" -output .build/universal/Tabby
  BIN=.build/universal/Tabby
else
  swift build -c release
  BIN=.build/release/Tabby
fi

APP=build/Tabby.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tabby"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# An explicitly passed SIGN_ID must work (releases must never fall back to ad-hoc).
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --sign "$SIGN_ID" "$APP"
  echo "Built $APP (signed with: $SIGN_ID)"
  SIGNED=1
fi
LOCAL_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')"
if [ -n "${SIGNED:-}" ]; then
  :
elif [ -n "$LOCAL_ID" ] && codesign --force --sign "$LOCAL_ID" "$APP"; then
  echo "Built $APP (signed with: $LOCAL_ID)"
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
