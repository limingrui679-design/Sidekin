#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_BUNDLE="$PROJECT_ROOT/artifacts/Sidekin.app"
CONTENTS="$APP_BUNDLE/Contents"
SIGN_IDENTITY="${CAINIAOPET_SIGN_IDENTITY:-}"
BUNDLE_ID="${CAINIAOPET_BUNDLE_ID:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

cd "$PROJECT_ROOT"
"$PROJECT_ROOT/Scripts/verify-theme-catalog.sh"
swift "$PROJECT_ROOT/Scripts/verify-character-assets.swift" \
  "$PROJECT_ROOT/Sources/SidekinApp/Resources/Characters"
swift run -c release SidekinSelfTest
swift run -c release SidekinAPISelfTest

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
RESOURCE_BUNDLE="$BIN_DIR/Sidekin_SidekinApp.bundle"

case "$RESOURCE_BUNDLE" in
  "$PROJECT_ROOT"/.build/*/release/Sidekin_SidekinApp.bundle) ;;
  *)
    print -u2 "Unexpected SwiftPM resource path; refusing to clean it: $RESOURCE_BUNDLE"
    exit 1
    ;;
esac

# SwiftPM can retain removed resources between builds. Recreate the exact
# generated bundle so a release never carries legacy character files.
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  rm -rf -- "$RESOURCE_BUNDLE"
fi

swift build -c release --arch arm64 --product Sidekin
swift build -c release --arch arm64 --product SidekinBridge

if [[ "$APP_BUNDLE" != "$PROJECT_ROOT/artifacts/Sidekin.app" ]]; then
  print -u2 "Unexpected app bundle path; refusing to replace it."
  exit 1
fi
if [[ -e "$APP_BUNDLE" ]]; then
  rm -rf -- "$APP_BUNDLE"
fi

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Sidekin" "$CONTENTS/MacOS/Sidekin"
cp "$BIN_DIR/SidekinBridge" "$CONTENTS/Resources/SidekinBridge"
cp "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
chmod 755 "$CONTENTS/MacOS/Sidekin" "$CONTENTS/Resources/SidekinBridge"

if [[ -n "$BUNDLE_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
fi

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
fi

PACKAGED_RESOURCE_BUNDLE="$CONTENTS/Resources/$(basename "$RESOURCE_BUNDLE")"
CHARACTER_COUNT="$(find "$PACKAGED_RESOURCE_BUNDLE" -type f -name '*.png' | wc -l | tr -d ' ')"
if [[ "$CHARACTER_COUNT" != "1000" ]]; then
  print -u2 "Expected exactly 1,000 packaged character models, found $CHARACTER_COUNT."
  exit 1
fi
if find "$PACKAGED_RESOURCE_BUNDLE" -type f \
  \( -name '*-guardian.png' -o -name '*-dreamer.png' \) | grep -q .; then
  print -u2 "Legacy four-stage character assets leaked into the release bundle."
  exit 1
fi

ICON_TEMP="$(mktemp -d /tmp/sidekin-icon.XXXXXX)"
trap 'rm -rf -- "$ICON_TEMP"' EXIT
ICONSET="$ICON_TEMP/AppIcon.iconset"
MASTER_ICON="$ICONSET/icon_512x512@2x.png"
mkdir -p "$ICONSET"
swift "$PROJECT_ROOT/Scripts/make-app-icon.swift" "$MASTER_ICON"

while read -r filename pixels; do
  /usr/bin/sips -z "$pixels" "$pixels" "$MASTER_ICON" --out "$ICONSET/$filename" >/dev/null
done <<'ICON_SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
ICON_SIZES

/usr/bin/iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"

SIGN_ARGUMENTS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi

# Sign nested code first, then the main executable and the outer bundle.
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$CONTENTS/Resources/SidekinBridge"
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$CONTENTS/MacOS/Sidekin"
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  print "Built local ad-hoc app: $APP_BUNDLE"
else
  print "Built Hardened Runtime app signed by: $SIGN_IDENTITY"
  print "App bundle: $APP_BUNDLE"
fi
