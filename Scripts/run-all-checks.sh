#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

swift build
swift run CainiaoPetSelfTest
swift run CainiaoPetAPISelfTest
swift "$PROJECT_ROOT/Scripts/verify-character-assets.swift" \
  "$PROJECT_ROOT/Sources/CainiaoPetApp/Resources/Characters"
swift build -c release

print "All source, mock API, asset, debug, and release checks passed."
