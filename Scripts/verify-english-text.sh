#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
exec node "$PROJECT_ROOT/Scripts/verify-english-text.mjs"
