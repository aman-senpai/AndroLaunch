#!/usr/bin/env bash
#
# Builds the macOS app.
#
# `-disable-sandbox` is required in this workspace: the harness runs commands in a
# file sandbox, and the Swift macro plugin server cannot apply its own nested
# sandbox there (SwiftUI's @State macro fails with "produced malformed response").
# The flag only affects compiler subprocess sandboxing; it does not change the app.
#
# Usage: scripts/build-macos.sh [Debug|Release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Debug}"
shift || true
DERIVED="${DERIVED_DATA_PATH:-/tmp/dd-androlaunch-$(whoami)}"

xcodebuild \
  -project "$ROOT/macos/AndroLaunch.xcodeproj" \
  -scheme AndroLaunch \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  OTHER_SWIFT_FLAGS="-disable-sandbox" \
  build "$@"

APP="$DERIVED/Build/Products/$CONFIG/AndroLaunch.app"
if [[ -d "$APP" ]]; then
  echo "app: $APP"
fi
