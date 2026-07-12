#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED_DATA="$ROOT/DerivedData-Release"
DIST="$ROOT/dist"
APP="$DIST/YTLite.app"

cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  print -u2 "XcodeGen is required. Install it with: brew install xcodegen"
  exit 1
fi

xcodegen generate
xcodebuild \
  -project YTLite.xcodeproj \
  -scheme YTLite \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

mkdir -p "$DIST"
rm -rf "$APP"
ditto --norsrc "$DERIVED_DATA/Build/Products/Release/YTLite.app" "$APP"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$DIST/YTLite-$VERSION-macOS.zip"
rm -f "$ZIP"
COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent "$APP" "$ZIP"

print "$APP"
print "$ZIP"
