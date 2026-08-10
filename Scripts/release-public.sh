#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SIGN_IDENTITY="${CAINIAOPET_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${CAINIAOPET_NOTARY_PROFILE:-}"
BUNDLE_ID="${CAINIAOPET_BUNDLE_ID:-}"

[[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]] || {
  print -u2 "Set CAINIAOPET_SIGN_IDENTITY to a Developer ID Application identity."
  exit 2
}
[[ -n "$NOTARY_PROFILE" ]] || {
  print -u2 "Set CAINIAOPET_NOTARY_PROFILE to a notarytool Keychain profile."
  exit 2
}
[[ "$BUNDLE_ID" == *.*.* ]] || {
  print -u2 "Set CAINIAOPET_BUNDLE_ID to the registered reverse-DNS bundle identifier."
  exit 2
}

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGN_IDENTITY"; then
  print -u2 "The requested Developer ID identity is not available in this Keychain."
  exit 1
fi

cd "$PROJECT_ROOT"
if [[ -n "$(/usr/bin/git status --porcelain --untracked-files=normal)" ]]; then
  print -u2 "Public releases require a clean Git worktree. Commit or remove pending changes first."
  exit 1
fi

CAINIAOPET_SIGN_IDENTITY="$SIGN_IDENTITY" \
CAINIAOPET_BUNDLE_ID="$BUNDLE_ID" \
  "$PROJECT_ROOT/Scripts/build-app.sh"
"$PROJECT_ROOT/Scripts/package-release.sh" --skip-build

APP_BUNDLE="$PROJECT_ROOT/artifacts/CainiaoPet.app"
ARCHIVE="$PROJECT_ROOT/artifacts/CainiaoPet-macOS-arm64.zip"
/usr/bin/xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"

# Rebuild the distribution archive so it contains the stapled app rather than
# the identical pre-staple upload copy.
"$PROJECT_ROOT/Scripts/package-release.sh" --skip-build
"$PROJECT_ROOT/Scripts/verify-release.sh" --public "$APP_BUNDLE" "$ARCHIVE"

print "Developer ID signing, notarization, stapling, Gatekeeper, and clean archive checks passed."
