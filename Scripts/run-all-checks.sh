#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

npm run verify
"$PROJECT_ROOT/Scripts/verify-theme-catalog.sh"
"$PROJECT_ROOT/Scripts/verify-english-text.sh"
swift "$PROJECT_ROOT/Scripts/verify-lineage-audit.swift"
swift build
swift run SidekinSelfTest
swift run SidekinAPISelfTest
swift build -c release

print "All current desktop, catalog, English-surface, historical Swift, mock API, debug, and release-build checks passed."
