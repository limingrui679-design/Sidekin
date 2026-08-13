#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SKIP_BUILD=0
if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=1
elif [[ "$#" != "0" ]]; then
  print -u2 "Usage: package-release.sh [--skip-build]"
  exit 2
fi

APP_BUNDLE="$PROJECT_ROOT/artifacts/Sidekin.app"
ARCHIVE="$PROJECT_ROOT/artifacts/Sidekin-macOS-arm64.zip"
EXTERNAL_MANIFEST="$PROJECT_ROOT/artifacts/Sidekin-macOS-arm64.RELEASE.json"
CHECKSUM="$PROJECT_ROOT/artifacts/Sidekin-macOS-arm64.zip.sha256"

if [[ "$SKIP_BUILD" == "0" ]]; then
  "$PROJECT_ROOT/Scripts/build-app.sh"
fi
[[ -d "$APP_BUNDLE" ]] || { print -u2 "Build the app before packaging."; exit 1; }

"$PROJECT_ROOT/Scripts/verify-release.sh" "$APP_BUNDLE"

PACKAGE_TEMP="$(mktemp -d /tmp/sidekin-package.XXXXXX)"
cleanup() {
  case "$PACKAGE_TEMP" in
    /tmp/sidekin-package.*) rm -rf -- "$PACKAGE_TEMP" ;;
  esac
}
trap cleanup EXIT

STAGING="$PACKAGE_TEMP/staging"
mkdir -p "$STAGING"
/usr/bin/ditto "$APP_BUNDLE" "$STAGING/Sidekin.app"
swift "$PROJECT_ROOT/Scripts/generate-release-manifest.swift" \
  "$STAGING/Sidekin.app" "$STAGING/RELEASE_MANIFEST.json"

mkdir -p "$PROJECT_ROOT/artifacts"
ARCHIVE_TEMP="$PROJECT_ROOT/artifacts/.Sidekin-macOS-arm64.$$.zip"
case "$ARCHIVE_TEMP" in
  "$PROJECT_ROOT"/artifacts/.Sidekin-macOS-arm64.*.zip) ;;
  *) print -u2 "Unexpected archive path."; exit 1 ;;
esac
rm -f -- "$ARCHIVE_TEMP"
(
  cd "$STAGING"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$ARCHIVE_TEMP" \
    Sidekin.app RELEASE_MANIFEST.json \
    -x '*.DS_Store' '__MACOSX/*' '*/._*'
)
mv -f -- "$ARCHIVE_TEMP" "$ARCHIVE"

swift "$PROJECT_ROOT/Scripts/generate-release-manifest.swift" \
  "$APP_BUNDLE" "$EXTERNAL_MANIFEST" "$ARCHIVE"
/usr/bin/shasum -a 256 "$ARCHIVE" > "$CHECKSUM"

"$PROJECT_ROOT/Scripts/verify-release.sh" "$APP_BUNDLE" "$ARCHIVE"
print "Packaged $ARCHIVE"
print "Release manifest: $EXTERNAL_MANIFEST"
print "SHA-256 file: $CHECKSUM"
