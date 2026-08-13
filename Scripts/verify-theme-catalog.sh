#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEMP_DIR="$(mktemp -d /tmp/cainiao-theme-catalog.XXXXXX)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

swift "$PROJECT_ROOT/Scripts/generate-theme-catalog.swift" \
  "$PROJECT_ROOT/ArtSources/ThemeCatalog" \
  "$TEMP_DIR/PetThemeCatalog.generated.swift" \
  "$TEMP_DIR/PET_THEME_CATALOG.json" >/dev/null

swift "$PROJECT_ROOT/Scripts/generate-art-prompts.swift" \
  "$TEMP_DIR/PET_THEME_CATALOG.json" \
  "$TEMP_DIR/Prompts" >/dev/null

if ! /usr/bin/cmp -s \
  "$TEMP_DIR/PetThemeCatalog.generated.swift" \
  "$PROJECT_ROOT/Sources/CainiaoPetCore/PetThemeCatalog.generated.swift"; then
  print -u2 "Generated Swift theme catalog is stale. Run Scripts/generate-theme-catalog.swift."
  exit 1
fi

if ! /usr/bin/cmp -s \
  "$TEMP_DIR/PET_THEME_CATALOG.json" \
  "$PROJECT_ROOT/ArtSources/PET_THEME_CATALOG.json"; then
  print -u2 "Combined JSON theme catalog is stale. Run Scripts/generate-theme-catalog.swift."
  exit 1
fi

if ! /usr/bin/diff -qr \
  "$TEMP_DIR/Prompts" \
  "$PROJECT_ROOT/ArtSources/Prompts" >/dev/null; then
  print -u2 "The 500 stored art prompts are stale. Run Scripts/generate-art-prompts.swift."
  exit 1
fi

print "Verified 100-theme catalog source, generated data, and all 500 art prompts."
