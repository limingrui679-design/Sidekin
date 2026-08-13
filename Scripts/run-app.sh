#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_BUNDLE="$PROJECT_ROOT/artifacts/Sidekin.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  "$PROJECT_ROOT/Scripts/build-app.sh"
fi

open "$APP_BUNDLE"
