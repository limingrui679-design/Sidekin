#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
TEXT_TARGETS=(
  "$PROJECT_ROOT/.gitattributes"
  "$PROJECT_ROOT/.github"
  "$PROJECT_ROOT/.gitignore"
  "$PROJECT_ROOT/README.md"
  "$PROJECT_ROOT/Package.swift"
  "$PROJECT_ROOT/Sources"
  "$PROJECT_ROOT/Scripts"
  "$PROJECT_ROOT/Support"
  "$PROJECT_ROOT/ArtSources"
  "$PROJECT_ROOT/docs"
)

# Use explicit character ranges instead of Unicode script extensions. Script
# extensions classify punctuation such as a middle dot as Han-adjacent even
# when the surrounding UI copy is English.
CJK_PATTERN='[\x{3400}-\x{4DBF}\x{4E00}-\x{9FFF}\x{F900}-\x{FAFF}\x{20000}-\x{2FA1F}\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{AC00}-\x{D7AF}]'

if rg -n --pcre2 "$CJK_PATTERN" "${TEXT_TARGETS[@]}"; then
  print -u2 "English-text verification failed: CJK text remains in project-facing files."
  exit 1
fi

print "Verified all project-facing source, catalog, prompts, metadata, and documentation contain no CJK text."
