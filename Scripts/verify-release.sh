#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PUBLIC_RELEASE=0
APP_BUNDLE=""
ARCHIVE=""

for argument in "$@"; do
  case "$argument" in
    --public) PUBLIC_RELEASE=1 ;;
    *.app) APP_BUNDLE="${argument:A}" ;;
    *.zip) ARCHIVE="${argument:A}" ;;
    *)
      print -u2 "Usage: verify-release.sh [--public] Sidekin.app [Sidekin.zip]"
      exit 2
      ;;
  esac
done

if [[ -z "$APP_BUNDLE" && -z "$ARCHIVE" ]]; then
  print -u2 "Provide an app bundle, a ZIP archive, or both."
  exit 2
fi

VERIFY_TEMP="$(mktemp -d /tmp/sidekin-verify.XXXXXX)"
cleanup() {
  case "$VERIFY_TEMP" in
    /tmp/sidekin-verify.*) rm -rf -- "$VERIFY_TEMP" ;;
  esac
}
trap cleanup EXIT

verify_app() {
  local app="$1"
  local label="$2"
  local info="$app/Contents/Info.plist"
  local main_executable="$app/Contents/MacOS/Sidekin"
  local bridge="$app/Contents/Resources/SidekinBridge"
  local resource_bundle="$app/Contents/Resources/Sidekin_SidekinApp.bundle"

  [[ -d "$app" ]] || { print -u2 "$label app bundle is missing: $app"; exit 1; }
  /usr/bin/plutil -lint "$info" >/dev/null
  [[ -x "$main_executable" ]] || { print -u2 "$label main executable is missing."; exit 1; }
  [[ -x "$bridge" ]] || { print -u2 "$label bridge executable is missing."; exit 1; }
  [[ -d "$resource_bundle" ]] || { print -u2 "$label resource bundle is missing."; exit 1; }

  local version
  local build
  local minimum_system
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
  minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
  [[ -n "$version" && -n "$build" && -n "$minimum_system" ]] || {
    print -u2 "$label version metadata is incomplete."
    exit 1
  }

  local app_archs
  local bridge_archs
  app_archs="$(/usr/bin/lipo -archs "$main_executable")"
  bridge_archs="$(/usr/bin/lipo -archs "$bridge")"
  [[ "$app_archs" == "arm64" ]] || {
    print -u2 "$label app architecture is '$app_archs', expected arm64."
    exit 1
  }
  [[ "$bridge_archs" == "arm64" ]] || {
    print -u2 "$label bridge architecture is '$bridge_archs', expected arm64."
    exit 1
  }

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  swift "$PROJECT_ROOT/Scripts/verify-character-assets.swift" "$resource_bundle"

  if [[ "$PUBLIC_RELEASE" == "1" ]]; then
    local signature_details
    signature_details="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
    if [[ "$signature_details" == *"Signature=adhoc"* \
      || "$signature_details" == *"TeamIdentifier=not set"* ]]; then
      print -u2 "$label is not signed with a Developer ID identity."
      exit 1
    fi
    if [[ "$signature_details" != *"runtime"* ]]; then
      print -u2 "$label is missing Hardened Runtime."
      exit 1
    fi
    /usr/sbin/spctl --assess --type exec --verbose=4 "$app"
    /usr/bin/xcrun stapler validate "$app"
  fi

  print "$label verified: version $version ($build), macOS $minimum_system+, arm64, 500 assets."
}

if [[ -n "$APP_BUNDLE" ]]; then
  verify_app "$APP_BUNDLE" "Built app"
fi

if [[ -n "$ARCHIVE" ]]; then
  [[ -f "$ARCHIVE" ]] || { print -u2 "Archive is missing: $ARCHIVE"; exit 1; }
  /usr/bin/unzip -tq "$ARCHIVE" >/dev/null
  ZIP_LIST="$(/usr/bin/zipinfo -1 "$ARCHIVE")"
  if print -r -- "$ZIP_LIST" | /usr/bin/grep -Eq \
    '(^|/)__MACOSX/|(^|/)\.DS_Store$|(^|/)\._[^/]+$'; then
    print -u2 "Archive contains forbidden macOS metadata."
    exit 1
  fi
  print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'Sidekin.app/Contents/Info.plist'
  print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'RELEASE_MANIFEST.json'

  /usr/bin/unzip -q "$ARCHIVE" -d "$VERIFY_TEMP/archive"
  EXTRACTED_APP="$VERIFY_TEMP/archive/Sidekin.app"
  EMBEDDED_MANIFEST="$VERIFY_TEMP/archive/RELEASE_MANIFEST.json"
  swift "$PROJECT_ROOT/Scripts/read-release-manifest.swift" \
    "$EMBEDDED_MANIFEST" schemaVersion >/dev/null
  verify_app "$EXTRACTED_APP" "Archived app"

  swift "$PROJECT_ROOT/Scripts/generate-release-manifest.swift" \
    "$EXTRACTED_APP" "$VERIFY_TEMP/extracted-manifest.json" >/dev/null
  EXPECTED_TREE="$(swift "$PROJECT_ROOT/Scripts/read-release-manifest.swift" \
    "$EMBEDDED_MANIFEST" appTreeSHA256)"
  ACTUAL_TREE="$(swift "$PROJECT_ROOT/Scripts/read-release-manifest.swift" \
    "$VERIFY_TEMP/extracted-manifest.json" appTreeSHA256)"
  [[ "$EXPECTED_TREE" == "$ACTUAL_TREE" ]] || {
    print -u2 "Archived app does not match its embedded release manifest."
    exit 1
  }

  if [[ -n "$APP_BUNDLE" ]]; then
    swift "$PROJECT_ROOT/Scripts/generate-release-manifest.swift" \
      "$APP_BUNDLE" "$VERIFY_TEMP/built-manifest.json" >/dev/null
    BUILT_TREE="$(swift "$PROJECT_ROOT/Scripts/read-release-manifest.swift" \
      "$VERIFY_TEMP/built-manifest.json" appTreeSHA256)"
    [[ "$BUILT_TREE" == "$ACTUAL_TREE" ]] || {
      print -u2 "Archive contents do not match the built app."
      exit 1
    }
  fi
  print "Archive verified: no __MACOSX, .DS_Store, AppleDouble, corruption, or manifest drift."
fi
