#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEXT_TARGETS=(
  "$PROJECT_ROOT/.gitattributes"
  "$PROJECT_ROOT/.github"
  "$PROJECT_ROOT/.gitignore"
  "$PROJECT_ROOT/README.md"
  "$PROJECT_ROOT/Package.swift"
  "$PROJECT_ROOT/package.json"
  "$PROJECT_ROOT/package-lock.json"
  "$PROJECT_ROOT/tsconfig.json"
  "$PROJECT_ROOT/Sources"
  "$PROJECT_ROOT/src"
  "$PROJECT_ROOT/tests"
  "$PROJECT_ROOT/Scripts"
  "$PROJECT_ROOT/Support"
  "$PROJECT_ROOT/ArtSources"
  "$PROJECT_ROOT/docs"
)

# The old product name appears only in narrowly scoped compatibility constants
# used to migrate existing saves, Hooks, Keychain access, and template imports.
LEGACY_BRAND_PATTERN='CainiaoPet|Cainiao Pet|cainiaopet|cainiao'
LEGACY_BRAND_ALLOWLIST=(
  'Sources/SidekinCore/PetPersistence.swift'
  'Sources/SidekinCore/CodexIntegration.swift'
  'Sources/SidekinCreator/APIKeyStore.swift'
  'Sources/SidekinApp/Views/ControlCenterView.swift'
  'Sources/SidekinSelfTest/main.swift'
  'src/main/paths.ts'
  'src/shared/codex.ts'
  'Scripts/verify-english-text.sh'
)

# Use explicit character ranges instead of Unicode script extensions. Script
# extensions classify punctuation such as a middle dot as Han-adjacent even
# when the surrounding UI copy is English.
CJK_PATTERN='[\x{3400}-\x{4DBF}\x{4E00}-\x{9FFF}\x{F900}-\x{FAFF}\x{20000}-\x{2FA1F}\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{AC00}-\x{D7AF}]'

if rg -n --pcre2 "$CJK_PATTERN" "${TEXT_TARGETS[@]}"; then
  print -u2 "English-text verification failed: CJK text remains in project-facing files."
  exit 1
fi

LEGACY_BRAND_HITS="$(
  cd "$PROJECT_ROOT"
  rg -l --hidden \
    --glob '!.git/**' \
    --glob '!.build/**' \
    --glob '!artifacts/**' \
    --glob '!*.png' \
    --glob '!*.jpg' \
    "$LEGACY_BRAND_PATTERN" . \
    | sed 's#^\./##' \
    | sort
)"
UNEXPECTED_LEGACY_HITS="$(
  print -r -- "$LEGACY_BRAND_HITS" \
    | while IFS= read -r path; do
        [[ -z "$path" || " ${LEGACY_BRAND_ALLOWLIST[*]} " == *" $path "* ]] || print -r -- "$path"
      done
)"
if [[ -n "$UNEXPECTED_LEGACY_HITS" ]]; then
  print -u2 "Brand verification failed: the retired name remains outside migration code:"
  print -u2 -- "$UNEXPECTED_LEGACY_HITS"
  exit 1
fi

print "Verified English-only project text and Sidekin branding; retired-name references are migration-only."
