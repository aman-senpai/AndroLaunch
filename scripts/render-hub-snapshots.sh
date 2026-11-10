#!/usr/bin/env bash
#
# Renders the Hub UI to PNG for visual review — no screen-recording permission,
# no window server interaction. Uses the app's DEBUG snapshot mode.
#
# Usage: scripts/render-hub-snapshots.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/hub-snapshots}"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED_DATA_PATH:-/tmp/dd-androlaunch-$(whoami)}"
APP="$DERIVED/Build/Products/$CONFIG/AndroLaunch.app"

if [[ ! -x "$APP/Contents/MacOS/AndroLaunch" ]]; then
  CONFIG="$CONFIG" DERIVED_DATA_PATH="$DERIVED" "$ROOT/scripts/build-macos.sh" "$CONFIG"
fi

mkdir -p "$OUT"
"$APP/Contents/MacOS/AndroLaunch" --render-hub-snapshots "$OUT"
echo "snapshots: $OUT"
ls -1 "$OUT"
