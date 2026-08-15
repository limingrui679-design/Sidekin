#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_DIR="$PROJECT_ROOT/artifacts"
VERSION="$(cd "$PROJECT_ROOT" && node -p 'require("./package.json").version')"
ARCHIVE="$OUTPUT_DIR/Sidekin-$VERSION-GitHub-Source.zip"
CHECKSUM="$ARCHIVE.sha256"

if ! /usr/bin/git -C "$PROJECT_ROOT" diff --quiet HEAD --; then
  print -u2 "Source archives require tracked files to match HEAD."
  exit 1
fi

node "$PROJECT_ROOT/Scripts/verify-expansion-plan.mjs" --full

mkdir -p "$OUTPUT_DIR"
PACKAGE_TEMP="$(mktemp -d /tmp/sidekin-source.XXXXXX)"
cleanup() {
  case "$PACKAGE_TEMP" in
    /tmp/sidekin-source.*) rm -rf -- "$PACKAGE_TEMP" ;;
  esac
}
trap cleanup EXIT

STAGING="$PACKAGE_TEMP/Sidekin"
mkdir -p "$STAGING"

TRACKED_LIST="$PACKAGE_TEMP/tracked-files"
/usr/bin/git -C "$PROJECT_ROOT" ls-files -z > "$TRACKED_LIST"
COPYFILE_DISABLE=1 /usr/bin/rsync -a --from0 --files-from="$TRACKED_LIST" \
  "$PROJECT_ROOT/" "$STAGING/"

"$STAGING/Scripts/verify-english-text.sh"
"$STAGING/Scripts/verify-theme-catalog.sh"
swift "$STAGING/Scripts/verify-lineage-audit.swift"
swift "$STAGING/Scripts/verify-character-assets.swift" \
  "$STAGING/Sources/SidekinApp/Resources/Characters"

rm -f -- "$ARCHIVE"
(
  cd "$PACKAGE_TEMP"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$ARCHIVE" Sidekin \
    -x '*.DS_Store' '__MACOSX/*' '*/._*'
)

/usr/bin/unzip -tq "$ARCHIVE" >/dev/null
ZIP_LIST="$(/usr/bin/zipinfo -1 "$ARCHIVE")"
if print -r -- "$ZIP_LIST" | /usr/bin/grep -Eq \
  '(^|/)__MACOSX/|(^|/)\.DS_Store$|(^|/)\._[^/]+$|(^|/)\.git/|(^|/)\.build/|(^|/)artifacts/'; then
  print -u2 "Source archive contains a forbidden generated or metadata path."
  exit 1
fi
print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'Sidekin/Package.swift'
print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'Sidekin/ArtSources/PET_THEME_CATALOG.json'
print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'Sidekin/docs/LINEAGE_AUDIT.md'
print -r -- "$ZIP_LIST" | /usr/bin/grep -qx 'Sidekin/docs/EXPANSION_AUDIT.md'

RESOURCE_COUNT="$(print -r -- "$ZIP_LIST" | /usr/bin/grep -Ec \
  '^Sidekin/Sources/SidekinApp/Resources/Characters/[^/]+\.png$')"
PROMPT_COUNT="$(print -r -- "$ZIP_LIST" | /usr/bin/grep -Ec \
  '^Sidekin/ArtSources/Prompts/[^/]+/[^/]+\.txt$')"
AUDIT_SHEET_COUNT="$(print -r -- "$ZIP_LIST" | /usr/bin/grep -Ec \
  '^Sidekin/ArtSources/AuditSheets/lineage-audit-[0-9]{2}\.png$')"
EXPANSION_AUDIT_SHEET_COUNT="$(print -r -- "$ZIP_LIST" | /usr/bin/grep -Ec \
  '^Sidekin/ArtSources/Expansion200/ReviewSheets/assets-[0-9]{2}\.jpg$')"
[[ "$RESOURCE_COUNT" == "1000" ]] || {
  print -u2 "Source archive contains $RESOURCE_COUNT final resources, expected 1,000."
  exit 1
}
[[ "$PROMPT_COUNT" == "1000" ]] || {
  print -u2 "Source archive contains $PROMPT_COUNT prompts, expected 1,000."
  exit 1
}
[[ "$AUDIT_SHEET_COUNT" == "20" ]] || {
  print -u2 "Source archive contains $AUDIT_SHEET_COUNT audit sheets, expected 20."
  exit 1
}
[[ "$EXPANSION_AUDIT_SHEET_COUNT" == "20" ]] || {
  print -u2 "Source archive contains $EXPANSION_AUDIT_SHEET_COUNT expansion audit sheets, expected 20."
  exit 1
}

(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "${ARCHIVE:t}" > "${CHECKSUM:t}"
)
print "Packaged local GitHub source snapshot: $ARCHIVE"
print "SHA-256 file: $CHECKSUM"
